import AppKit
import CloudDropCore
import UniformTypeIdentifiers

/// Owns the menu bar icon: it receives Drops, shows the icon states and builds the menu.
@MainActor
final class StatusController: NSObject, NSWindowDelegate, NSDraggingDestination, NSMenuDelegate {
    private enum Flash { case success, failure }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let queue = UploadQueue()
    private let history = LinkHistory()
    private let menu = NSMenu()
    private let promiseQueue = OperationQueue()
    private lazy var settings = SettingsWindowController { [weak self] saved in
        self?.storedCredentials = .success(saved)
        self?.history.reset()
    }

    /// Nil until the Keychain has been read. A success holds nil when no Cloudinary URL is saved.
    private var storedCredentials: Result<CloudinaryCredentials?, CredentialsError>?
    private var flash: Flash?
    private var flashToken = 0

    private var isMenuOpen = false
    /// What the open menu's Link History section shows, to tell a real change from a thumbnail arriving.
    private var shownHistory: [String] = []
    private var rowViews: [String: HistoryRowView] = [:]
    /// Survives a rebuild of the open menu, so the highlight stays on the same entry.
    private var highlightedLink: URL?

    override init() {
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeft

        // The status item's window forwards drag events to its delegate.
        let window = statusItem.button?.window
        window?.registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        window?.delegate = self

        queue.credentials = { [weak self] in
            guard let self else { throw CredentialsError.notSet }
            return try self.credentials()
        }
        queue.onEvent = { [weak self] event in self?.handle(event) }
        queue.onUploaded = { [weak self] entry, thumbnail in self?.history.add(entry, thumbnail: thumbnail) }
        queue.onDeleted = { [weak self] entry in self?.history.remove(entry) }
        history.credentials = { [weak self] in try? self?.credentials() }
        history.onChange = { [weak self] in self?.historyChanged() }
        render()
        // So the first click already shows the Link History.
        history.refresh()
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

    private func readCredentials() {
        do {
            storedCredentials = .success(try KeychainStore.load())
        } catch {
            storedCredentials = .failure(error)
            log.error("\(String(describing: error), privacy: .public)")
            queue.refuse(error.localizedDescription)
        }
    }

    /// Captures saved to Downloads by the cleanup at the last quit or at this launch.
    func reportCapturesSaved(_ count: Int) {
        queue.refuse(TemporaryFiles.capturesSavedMessage(count: count))
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
            if case .success = storedCredentials { history.refresh() }
        }
        do throws(CredentialsError) {
            _ = try credentials()
        } catch {
            // A Capture is the only copy, so it goes to Downloads rather than vanish with the drag.
            let saved = fileURLs.filter(TemporaryFiles.isCapture).compactMap { TemporaryFiles.saveCaptureToDownloads($0) }
            let message = error.localizedDescription
            queue.refuse(saved.isEmpty ? message : TemporaryFiles.mentioningCaptureSaved(message))
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
    /// the same Drop that are waiting to upload.
    private func receive(_ promises: [NSFilePromiseReceiver]) {
        for promise in promises {
            let folder = TemporaryFiles.dropFolder()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            promise.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: promiseQueue) { [weak self] url, error in
                Task { @MainActor in
                    if let error {
                        TemporaryFiles.remove(url)
                        self?.queue.refuse("Couldn't receive the dropped file: \(error.localizedDescription)")
                    } else {
                        self?.queue.add(fileURL: url, received: true)
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
            if let progress = queue.progress {
                symbol = "arrow.up.circle"
                title = " \(Int(progress * 100))%"
            } else {
                symbol = "icloud.and.arrow.up"
            }
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "CloudDrop")
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)])
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Shows what's already known now; a fresh list replaces it in place when it arrives.
        history.refresh()
        buildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        highlightedLink = nil
    }

    /// A refresh or a thumbnail finished. An open menu is only rebuilt when its Link History section changed,
    /// so rows don't shift under the pointer for nothing.
    private func historyChanged() {
        guard isMenuOpen else { return }
        guard historySection() == shownHistory else {
            buildMenu()
            for item in menu.items {
                (item.view as? HistoryRowView)?.isHighlighted = item.representedObject as? URL == highlightedLink
            }
            return
        }
        for entry in history.entries {
            if let image = history.thumbnail(for: entry) { rowViews[entry.publicID]?.setThumbnail(image) }
        }
    }

    private func historySection() -> [String] {
        var section = history.entries.map(\.publicID)
        switch history.currentProblem {
        case let .failed(reason)?: section.append("failed: \(reason)")
        case let .paused(until)?: section.append("paused: \(until)")
        case nil: break
        }
        if history.entries.isEmpty { section.append(isLoading ? "loading" : "empty") }
        return section
    }

    private var isLoading: Bool { !history.hasLoaded && history.isFetching }

    private func buildMenu() {
        menu.removeAllItems()
        rowViews = [:]
        shownHistory = historySection()

        if let error = queue.lastError {
            let item = NSMenuItem(title: "⚠︎ " + MenuText.truncateMiddle(error, maxLength: 60), action: nil, keyEquivalent: "")
            item.toolTip = error
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        if history.entries.isEmpty {
            let empty = NSMenuItem(title: isLoading ? "Loading…" : "No uploads yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let sizes = history.entries.map { $0.byteCount.map(MenuText.fileSize) ?? "" }
            let times = history.entries.map { HistoryTime.label(for: $0.uploadedAt) }
            let sizeWidth = HistoryRowView.columnWidth(sizes)
            let timeWidth = HistoryRowView.columnWidth(times)
            for (index, entry) in history.entries.enumerated() {
                // The action is what Return sends for a highlighted row; clicks go through the view.
                let item = NSMenuItem(title: entry.filename, action: #selector(copyHistoryEntry(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.shareLink
                let row = HistoryRowView(
                    entry: entry,
                    thumbnail: history.thumbnail(for: entry),
                    size: sizes[index],
                    time: times[index],
                    fullTime: HistoryTime.full(entry.uploadedAt),
                    sizeWidth: sizeWidth,
                    timeWidth: timeWidth,
                    onCopy: { [weak self] in
                        self?.menu.cancelTracking()
                        self?.queue.recopy(entry.shareLink)
                    },
                    onOpen: { [weak self] in
                        self?.menu.cancelTracking()
                        NSWorkspace.shared.open(entry.shareLink)
                    },
                    onDelete: { [weak self] in
                        self?.menu.cancelTracking()
                        // After the menu has finished closing, so the alert isn't run from inside its tracking loop.
                        Task { @MainActor in self?.confirmDelete(entry) }
                    })
                item.view = row
                rowViews[entry.publicID] = row
                menu.addItem(item)
            }
        }

        if let problem = history.currentProblem {
            let item: NSMenuItem
            switch problem {
            case let .failed(reason):
                item = NSMenuItem(title: "Couldn't refresh Link History", action: nil, keyEquivalent: "")
                item.toolTip = reason
            case let .paused(until):
                item = NSMenuItem(title: "Link History paused until \(HistoryTime.clock(until))", action: nil, keyEquivalent: "")
                item.toolTip = HistoryFetchError.rateLimited(until: until).localizedDescription
            }
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Set Cloudinary URL…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit CloudDrop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        highlightedLink = item?.representedObject as? URL
        for menuItem in menu.items {
            (menuItem.view as? HistoryRowView)?.isHighlighted = menuItem === item
        }
    }

    @objc private func copyHistoryEntry(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? URL else { return }
        queue.recopy(link)
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

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItem.toggle()
        } catch {
            queue.refuse("Launch at Login: \(error.localizedDescription)")
        }
    }

    private func showSettings() {
        settings.show(current: try? credentials())
    }
}
