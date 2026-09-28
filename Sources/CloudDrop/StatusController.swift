import AppKit
import CloudDropCore
import UniformTypeIdentifiers

/// Owns the menu bar icon: it receives Drops, shows the icon states and builds the menu.
@MainActor
final class StatusController: NSObject, NSWindowDelegate, NSDraggingDestination, NSMenuDelegate {
    private enum Flash { case success, failure }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let queue = UploadQueue()
    private let menu = NSMenu()
    private let promiseQueue = OperationQueue()
    private lazy var settings = SettingsWindowController { [weak self] saved in
        self?.cachedCredentials = saved
    }

    private var cachedCredentials: CloudinaryCredentials?
    private var didLoadCredentials = false
    private var flash: Flash?
    private var flashToken = 0

    override init() {
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeft

        // The status item's window forwards drag events to its delegate.
        let window = statusItem.button?.window
        window?.registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        window?.delegate = self

        queue.credentials = { [weak self] in self?.credentials() }
        queue.onEvent = { [weak self] event in self?.handle(event) }
        render()
    }

    // MARK: Credentials

    /// Read lazily so the Keychain prompt after a rebuild appears on first use, not at login.
    private func credentials() -> CloudinaryCredentials? {
        if !didLoadCredentials {
            cachedCredentials = KeychainStore.load()
            didLoadCredentials = true
        }
        return cachedCredentials
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

        guard credentials() != nil else {
            queue.refuse("Set Cloudinary URL first")
            showSettings()
            return true
        }

        let fileURLs = Self.fileURLs(in: pasteboard)
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

    private func receive(_ promises: [NSFilePromiseReceiver]) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("clouddrop-drops/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for promise in promises {
            promise.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: promiseQueue) { [weak self] url, error in
                Task { @MainActor in
                    if let error {
                        self?.queue.refuse("Couldn't receive the dropped file: \(error.localizedDescription)")
                    } else {
                        self?.queue.add(fileURL: url, isTemporary: true)
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
        menu.removeAllItems()

        if let error = queue.lastError {
            let item = NSMenuItem(title: "⚠︎ " + MenuText.truncateMiddle(error, maxLength: 60), action: nil, keyEquivalent: "")
            item.toolTip = error
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        if queue.history.isEmpty {
            let empty = NSMenuItem(title: "No uploads yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let time = DateFormatter()
            time.dateFormat = "HH:mm"
            for (index, entry) in queue.history.enumerated() {
                let item = NSMenuItem(
                    title: "\(MenuText.truncateMiddle(entry.filename)) · \(time.string(from: entry.uploadedAt))",
                    action: #selector(copyHistoryEntry(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.toolTip = entry.link.absoluteString
                menu.addItem(item)
            }
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

    @objc private func copyHistoryEntry(_ sender: NSMenuItem) {
        guard queue.history.indices.contains(sender.tag) else { return }
        queue.recopy(queue.history[sender.tag])
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
        settings.show(current: credentials())
    }
}
