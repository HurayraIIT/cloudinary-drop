import AppKit
import CloudDropCore
import UniformTypeIdentifiers

/// Owns the menu bar icon: it receives Drops, shows the icon states and presents the Link History.
@MainActor
final class StatusController: NSObject, NSWindowDelegate, NSDraggingDestination, NSMenuDelegate, NSPopoverDelegate {
    private enum Flash { case success, failure }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let queue = UploadQueue()
    private let history = LinkHistory()
    private let usage = UsageTracker()
    private let popover = NSPopover()
    private let content = HistoryPopoverController()
    private let settingsMenu = NSMenu()
    private let promiseQueue = OperationQueue()
    private lazy var settings = SettingsWindowController { [weak self] saved in
        self?.storedCredentials = .success(saved)
        self?.history.reset()
        self?.usage.reset()
    }

    /// Nil until the Keychain has been read. A success holds nil when no Cloudinary URL is saved.
    private var storedCredentials: Result<CloudinaryCredentials?, CredentialsError>?
    private var flash: Flash?
    private var flashToken = 0

    private var isSettingsMenuOpen = false
    private var displayedError: String?

    override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.hasFullSizeContent = true
        popover.contentViewController = PopoverBackgroundController(content: content)
        settingsMenu.delegate = self
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        content.thumbnail = { [weak self] entry in self?.history.thumbnail(for: entry) }
        content.onVisibleEntries = { [weak self] ids in self?.history.showThumbnails(for: ids) }
        content.onCopy = { [weak self] entry in
            self?.popover.performClose(nil)
            self?.queue.recopy(entry.shareLink)
        }
        content.onOpen = { [weak self] entry in
            self?.popover.performClose(nil)
            NSWorkspace.shared.open(entry.shareLink)
        }
        content.onDelete = { [weak self] entry in
            self?.popover.performClose(nil)
            Task { @MainActor in self?.confirmDelete(entry) }
        }
        content.onDismiss = { [weak self] in self?.popover.performClose(nil) }
        content.onCloudinaryURL = { [weak self] in self?.showSettings() }
        content.onSettings = { [weak self] button in self?.showSettingsMenu(from: button) }
        content.onResize = { [weak self] size in self?.popover.contentSize = size }
        statusItem.button?.imagePosition = .imageLeft

        // The status item's window forwards drag events to its delegate.
        let window = statusItem.button?.window
        window?.registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        window?.delegate = self

        queue.credentials = { [weak self] in
            guard let self else { throw CredentialsError.notSet }
            return try self.credentials()
        }
        queue.compression = { VideoCompression.setting }
        queue.opensShareLinks = { OpenShareLinks.isEnabled }
        queue.onEvent = { [weak self] event in self?.handle(event) }
        // An Upload or Delete that finishes after the Cloudinary URL changed to another cloud belongs to the old
        // one, so it's kept out of the new Link History. Its Share Link was still copied (and opened, if that's on).
        queue.onUploaded = { [weak self] entry, thumbnail, cloudName in
            guard let self, self.isCurrentCloud(cloudName) else { return }
            self.history.add(entry, thumbnail: thumbnail)
            self.usage.countsChanged()
        }
        queue.onDeleted = { [weak self] entry, cloudName in
            guard let self, self.isCurrentCloud(cloudName) else { return }
            self.history.remove(entry)
            self.usage.countsChanged()
        }
        history.credentials = { [weak self] in try? self?.credentials() }
        history.onChange = { [weak self] in self?.updatePopover() }
        history.onThumbnail = { [weak self] id in self?.content.updateThumbnail(for: id) }
        usage.credentials = { [weak self] in try? self?.credentials() }
        usage.isPaused = { [weak self] in self?.history.isPaused ?? false }
        usage.onRateLimited = { [weak self] until in self?.history.pause(until: until) }
        usage.onChange = { [weak self] in self?.updatePopover() }
        render()
        // So the first click already shows the Link History and the Usage line.
        history.refresh()
        usage.refresh()
    }

    // MARK: Credentials

    /// Read once and cached. The first read happens at launch, for the Link History, so after a rebuild
    /// the Keychain prompt appears when the new build starts. A failed read is only tried again by the
    /// next Drop, so choosing Deny doesn't bring the prompt back on every click of the icon.
    private func credentials() throws(CredentialsError) -> CloudinaryCredentials {
        if storedCredentials == nil { readCredentials() }
        guard let credentials = try storedCredentials?.get() else { throw .notSet }
        return credentials
    }

    private func isCurrentCloud(_ cloudName: String) -> Bool {
        guard case let .success(current?) = storedCredentials else { return false }
        return current.cloudName == cloudName
    }

    private func readCredentials() {
        do {
            storedCredentials = .success(try KeychainStore.load())
        } catch {
            storedCredentials = .failure(error)
            log.error("\(String(describing: error), privacy: .public)")
            queue.refuse(error.localizedDescription)
        }
    }

    /// Stops a running compression, at quit.
    func stop() {
        queue.stop()
    }

    /// Captures saved to Downloads by the cleanup at the last quit or at this launch, and any it couldn't save.
    func reportLeftoverCaptures(_ message: String) {
        queue.refuse(message)
    }

    // MARK: Drops

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        statusItem.button?.highlight(false)
    }

    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        statusItem.button?.highlight(false)
        let pasteboard = sender.draggingPasteboard
        queue.beginDrop()
        let fileURLs = Self.fileURLs(in: pasteboard)

        if case .failure = storedCredentials {
            readCredentials()
            if case .success = storedCredentials {
                history.refresh()
                usage.refresh()
            }
        }
        do throws(CredentialsError) {
            _ = try credentials()
        } catch {
            // A Capture is the only copy, so it goes to Downloads rather than vanish with the drag. One that can't be
            // saved waits in its capture folder for the sweep at quit or the next launch.
            let captures = fileURLs.filter(TemporaryFiles.isCapture).map { TemporaryFiles.keep(capture: $0) }
            let saved = captures.compactMap { TemporaryFiles.saveToDownloads($0) }
            var message = error.localizedDescription
            if !saved.isEmpty { message = TemporaryFiles.mentioningCaptureSaved(message) }
            if saved.count < captures.count { message = TemporaryFiles.mentioningCaptureNotSaved(message) }
            queue.refuse(message)
            if case .notSet = error { showSettings() }
            return true
        }

        if !fileURLs.isEmpty {
            fileURLs.forEach { queue.add(fileURL: $0) }
        } else {
            receive(Self.promises(in: pasteboard))
        }
        return true
    }

    /// Any file drag is accepted (non-media files are refused with a Last Error), but the icon
    /// only highlights when the drag holds at least one image or video.
    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        let urls = Self.fileURLs(in: pasteboard)
        let promises = urls.isEmpty ? Self.promises(in: pasteboard) : []
        guard !urls.isEmpty || !promises.isEmpty else { return [] }

        let hasMedia = urls.contains { MediaKind(fileExtension: $0.pathExtension) != nil }
            || promises.contains { $0.fileTypes.contains { UTType($0).flatMap(MediaKind.init(type:)) != nil } }
        statusItem.button?.highlight(hasMedia)
        return .copy
    }

    /// Each promise gets its own folder, so a failed one only removes its own file, never the files from
    /// the same Drop that are waiting to upload. Each also gets its place in the Upload Queue now, so the
    /// files keep their drop order whichever arrives first.
    private func receive(_ promises: [NSFilePromiseReceiver]) {
        for promise in promises {
            let place = queue.reserve()
            let folder = TemporaryFiles.dropFolder()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            promise.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: promiseQueue) { [weak self] url, error in
                Task { @MainActor in
                    if let error {
                        TemporaryFiles.remove(url)
                        self?.queue.release(place, refusing: "Couldn't receive the dropped file: \(error.localizedDescription)")
                    } else {
                        self?.queue.add(fileURL: url, place: place)
                    }
                }
            }
        }
    }

    private static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    private static func promises(in pasteboard: NSPasteboard) -> [NSFilePromiseReceiver] {
        pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
    }

    // MARK: Icon

    private func handle(_ event: UploadQueue.Event) {
        switch event {
        case .changed: render()
        case .succeeded: show(.success)
        case .failed: show(.failure)
        }
    }

    private func show(_ newFlash: Flash) {
        flash = newFlash
        flashToken += 1
        let token = flashToken
        render()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.flashToken == token else { return }
            self.flash = nil
            self.render()
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        var title = ""
        let symbol: String
        switch flash {
        case .success: symbol = "checkmark.circle"
        case .failure: symbol = "xmark.circle"
        case nil:
            switch queue.activity {
            case .compressing?: symbol = "arrow.down.right.and.arrow.up.left"
            case .uploading?: symbol = "arrow.up.circle"
            case nil: symbol = "icloud.and.arrow.up"
            }
            if let percent = queue.activity?.percent { title = " \(percent)%" }
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "CloudDrop")
        if queue.lastError != displayedError { updatePopover() }
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)])
    }

    // MARK: Link History

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        content.maximumHeight = (button.window?.screen?.visibleFrame.height ?? 800) - 60
        history.refresh()
        usage.refresh()
        updatePopover(force: true)
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        content.beginBrowsing()
    }

    private func updatePopover(force: Bool = false) {
        guard (popover.isShown || force), !isSettingsMenuOpen else { return }
        content.update(entries: history.entries, isLoading: !history.hasLoaded && history.isFetching,
                       problem: history.currentProblem, usage: usage.usage.line, lastError: queue.lastError)
        displayedError = queue.lastError
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool { !isSettingsMenuOpen }

    func popoverDidClose(_ notification: Notification) {
        content.endBrowsing()
    }

    private func showSettingsMenu(from button: NSView) {
        isSettingsMenuOpen = true
        let chosen = settingsMenu.popUp(positioning: nil, at: NSPoint(x: button.bounds.maxX, y: button.bounds.maxY), in: button)
        isSettingsMenuOpen = false
        if chosen { popover.performClose(nil) }
        updatePopover()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        buildSettingsMenu()
    }

    /// Built each time it opens, so it checks for ffmpeg then.
    private func buildSettingsMenu() {
        settingsMenu.removeAllItems()
        let openItem = NSMenuItem(title: "Open Share Links in Browser", action: #selector(toggleOpenShareLinks), keyEquivalent: "")
        openItem.target = self
        openItem.state = OpenShareLinks.isEnabled ? .on : .off
        settingsMenu.addItem(openItem)

        settingsMenu.addItem(.separator())
        addCompressionSection(VideoCompression.setting)
        settingsMenu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItem.isEnabled ? .on : .off
        settingsMenu.addItem(loginItem)
    }

    /// Compress Videos, and its Quality Levels while it's on. Without ffmpeg it's disabled and unchecked,
    /// whatever is saved, so the saved choice comes back once ffmpeg is installed.
    private func addCompressionSection(_ compression: CompressionSetting) {
        let toggle = NSMenuItem(title: "Compress Videos",
                                action: compression == .noFFmpeg ? nil : #selector(toggleCompression), keyEquivalent: "")
        toggle.target = self
        toggle.state = compression.isOn ? .on : .off
        settingsMenu.addItem(toggle)

        switch compression {
        case let .on(selected):
            for level in QualityLevel.allCases {
                let item = NSMenuItem(title: level.menuTitle, action: #selector(chooseQualityLevel(_:)), keyEquivalent: "")
                item.target = self
                item.tag = level.rawValue
                item.indentationLevel = 1
                item.state = level == selected ? .on : .off
                settingsMenu.addItem(item)
            }
        case .noFFmpeg:
            let item = NSMenuItem(title: "Please install ffmpeg", action: nil, keyEquivalent: "")
            item.indentationLevel = 1
            item.isEnabled = false
            settingsMenu.addItem(item)
        case .off:
            break
        }
    }

    /// Names the file and shows its thumbnail, because a Delete can't be undone. Cancel is the default button.
    private func confirmDelete(_ entry: HistoryEntry) {
        let alert = NSAlert()
        alert.messageText = "Delete \u{201C}\(entry.filename)\u{201D}?"
        alert.informativeText = "Its Share Link will stop working. This can't be undone."
        alert.icon = history.thumbnail(for: entry) ?? NSImage(
            systemSymbolName: entry.kind == .video ? "film" : "photo", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 48, weight: .regular))
        let cancel = alert.addButton(withTitle: "Cancel")
        let delete = alert.addButton(withTitle: "Delete")
        delete.hasDestructiveAction = true
        cancel.keyEquivalent = "\r"
        NSApp.activate()
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        queue.delete(entry)
    }

    @objc private func toggleOpenShareLinks() {
        OpenShareLinks.isEnabled.toggle()
    }

    @objc private func toggleCompression() {
        VideoCompression.isEnabled.toggle()
    }

    @objc private func chooseQualityLevel(_ sender: NSMenuItem) {
        guard let level = QualityLevel(rawValue: sender.tag) else { return }
        VideoCompression.quality = level
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItem.toggle()
        } catch {
            queue.refuse("Launch at Login: \(error.localizedDescription)")
        }
    }

    private func showSettings() {
        popover.performClose(nil)
        settings.show(current: try? credentials())
    }
}
