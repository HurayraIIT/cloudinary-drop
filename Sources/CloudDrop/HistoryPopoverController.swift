import AppKit
import CloudDropCore

/// Keeps the scrollable table separate from the commands, which never move as the Link History grows.
@MainActor
final class HistoryPopoverController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = HistoryTableView()
    private let scroll = NSScrollView()
    private let heading = NSTextField(labelWithString: "Link History")
    private let count = NSTextField(labelWithString: "")
    private let empty = NSTextField(labelWithString: "")
    private let problemLabel = NSTextField(labelWithString: "")
    private let divider = NSBox()
    private let quitDivider = NSBox()
    private let errorScroll = NSScrollView()
    private let urlButton = CommandButton(title: "Set Cloudinary URL…", shortcut: "⌘,")
    private let settingsButton = CommandButton(title: "Settings", symbol: "gearshape", shortcut: "›")
    private let quitButton = CommandButton(title: "Quit CloudDrop", shortcut: "⌘Q")
    private var usageView: UsageRowView?
    private var entries: [HistoryEntry] = []
    private var shownError: String?
    private var shownUsage: String?
    private var hasProblem = false
    private var isBrowsing = false
    private var isUpdating = false
    private weak var hoveredCommand: NSButton?

    var maximumHeight: CGFloat = 700
    var thumbnail: (HistoryEntry) -> NSImage? = { _ in nil }
    var onVisibleEntries: ([String]) -> Void = { _ in }
    var onCopy: (HistoryEntry) -> Void = { _ in }
    var onOpen: (HistoryEntry) -> Void = { _ in }
    var onDelete: (HistoryEntry) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    var onCloudinaryURL: () -> Void = {}
    var onSettings: (NSView) -> Void = { _ in }
    var onResize: (NSSize) -> Void = { _ in }

    override func loadView() {
        let root = PopoverView(frame: NSRect(x: 0, y: 0, width: HistoryRowView.width, height: 450))
        root.onCloudinaryURL = { [weak self] in self?.onCloudinaryURL() }
        root.onDismiss = { [weak self] in self?.onDismiss() }
        view = root
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("History"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.rowHeight = HistoryRowView.height
        table.intercellSpacing = .zero
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.backgroundColor = .clear
        table.focusRingType = .none
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.onCopy = { [weak self] in self?.copySelection() }
        table.onDismiss = { [weak self] in self?.onDismiss() }
        table.setAccessibilityLabel("Link History")
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        errorScroll.drawsBackground = false
        errorScroll.automaticallyAdjustsContentInsets = false
        errorScroll.hasVerticalScroller = true
        errorScroll.autohidesScrollers = true
        errorScroll.scrollerStyle = .overlay
        heading.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        count.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        count.textColor = .secondaryLabelColor
        count.alignment = .right
        empty.font = NSFont.menuFont(ofSize: 0)
        empty.textColor = .secondaryLabelColor
        empty.alignment = .center
        problemLabel.font = NSFont.systemFont(ofSize: 11)
        problemLabel.textColor = .secondaryLabelColor
        problemLabel.lineBreakMode = .byTruncatingTail
        divider.boxType = .separator
        quitDivider.boxType = .separator
        urlButton.onClick = { [weak self] in self?.onCloudinaryURL() }
        settingsButton.onClick = { [weak self] in
            guard let self else { return }
            onSettings(settingsButton)
        }
        quitButton.onClick = { NSApp.terminate(nil) }
        for command in [urlButton, settingsButton, quitButton] {
            command.onHoverChanged = { [weak self, weak command] hovered in
                guard let self, let command else { return }
                if hovered {
                    hoveredCommand = command
                    table.deselectAll(nil)
                } else if hoveredCommand === command {
                    hoveredCommand = nil
                }
            }
        }
        for child in [errorScroll, heading, count, scroll, empty, problemLabel, divider, urlButton, settingsButton, quitDivider, quitButton] {
            root.addSubview(child)
        }
    }

    func update(entries newEntries: [HistoryEntry], isLoading: Bool, problem: RefreshStatus.Problem?,
                usage: String?, lastError: String?) {
        loadViewIfNeeded()
        isUpdating = true
        let oldEntries = entries
        let visible = table.rows(in: scroll.documentVisibleRect)
        let topIndex = visible.location == NSNotFound ? 0 : min(visible.location, max(0, entries.count - 1))
        let offset = entries.isEmpty ? 0 : scroll.contentView.bounds.minY - table.rect(ofRow: topIndex).minY
        let selectedID = entries.indices.contains(table.selectedRow) ? entries[table.selectedRow].publicID : nil
        let focusedAction = selectedCell?.actionButtons.firstIndex { $0 === view.window?.firstResponder }
        let changed = entries != newEntries
        entries = newEntries
        if changed { table.reloadData() }
        count.stringValue = entries.isEmpty ? "" : "\(entries.count) latest"
        empty.stringValue = isLoading ? "Loading…" : "No uploads yet"
        empty.isHidden = !entries.isEmpty
        hasProblem = problem != nil
        switch problem {
        case let .failed(reason)?:
            problemLabel.stringValue = "Couldn't refresh Link History"
            problemLabel.toolTip = reason
        case let .paused(until)?:
            problemLabel.stringValue = "Link History paused until \(HistoryTime.clock(until))"
            problemLabel.toolTip = HistoryFetchError.rateLimited(until: until).localizedDescription
        case nil:
            problemLabel.stringValue = ""
            problemLabel.toolTip = nil
        }
        problemLabel.isHidden = !hasProblem
        if lastError != shownError {
            shownError = lastError
            errorScroll.documentView = lastError.map { LastErrorRowView(message: $0) }
        }
        errorScroll.isHidden = lastError == nil
        if usage != shownUsage {
            shownUsage = usage
            usageView?.removeFromSuperview()
            usageView = usage.map { UsageRowView(line: $0) }
            if let usageView { view.addSubview(usageView) }
        }
        layoutContent()
        if changed {
            if let selectedID, let row = entries.firstIndex(where: { $0.publicID == selectedID }) {
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            } else {
                table.deselectAll(nil)
            }
        }
        // Anchor to a surviving entry, not an index: inserts above and Deletes must not jump the viewport.
        if isBrowsing, !oldEntries.isEmpty {
            let followingIDs = oldEntries.dropFirst(topIndex).map(\.publicID)
            let anchor = followingIDs.lazy.compactMap { id in self.entries.firstIndex { $0.publicID == id } }.first
            let row = anchor ?? min(topIndex, max(0, entries.count - 1))
            scroll(to: entries.isEmpty ? 0 : table.rect(ofRow: row).minY + offset)
        }
        isUpdating = false
        updateHighlights()
        if changed, let focusedAction {
            view.window?.makeFirstResponder(selectedCell?.actionButtons[focusedAction] ?? table)
        }
        viewportChanged()
    }

    func beginBrowsing() {
        isUpdating = true
        isBrowsing = true
        // Recompute relative dates on each opening, including across midnight, without a timer.
        table.reloadData()
        scroll(to: 0)
        if !entries.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        view.window?.makeFirstResponder(table)
        view.window?.autorecalculatesKeyViewLoop = false
        updateKeyViews()
        isUpdating = false
        viewportChanged()
    }

    func endBrowsing() {
        isBrowsing = false
        for command in [urlButton, settingsButton, quitButton] { command.clearHover() }
        onVisibleEntries([])
    }

    func updateThumbnail(for id: String) {
        guard isBrowsing, let row = entries.firstIndex(where: { $0.publicID == id }),
              let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? HistoryRowView,
              let image = thumbnail(entries[row]) else { return }
        cell.setThumbnail(image)
    }

    private func layoutContent() {
        let width = HistoryRowView.width
        let historyHeight = min(HistoryRowView.height * 7, max(HistoryRowView.height, maximumHeight - 180))
        let normalHeight = 39 + historyHeight + (hasProblem ? 24 : 0) + 9 + (usageView == nil ? 0 : 30) + 52 + 8 + 26 + 8
        let errorHeight = min(errorScroll.documentView?.frame.height ?? 0, max(0, maximumHeight - normalHeight - 8))
        let errorSpace = shownError == nil ? 0 : errorHeight + 8
        var y: CGFloat = errorSpace
        errorScroll.frame = NSRect(x: 0, y: 0, width: width, height: errorHeight)
        // A first-open error can be installed while the scroll view is still zero-width.
        if let error = errorScroll.documentView {
            error.setFrameSize(NSSize(width: width, height: error.frame.height))
        }
        heading.frame = NSRect(x: 14, y: y + 12, width: 230, height: 18)
        count.frame = NSRect(x: 250, y: y + 12, width: width - 264, height: 18)
        y += 39
        scroll.frame = NSRect(x: 6, y: y, width: width - 12, height: historyHeight)
        table.tableColumns[0].width = scroll.contentSize.width
        empty.frame = NSRect(x: 14, y: y + historyHeight / 2 - 10, width: width - 28, height: 20)
        y += historyHeight
        problemLabel.frame = NSRect(x: 14, y: y + 5, width: width - 28, height: 18)
        if hasProblem { y += 24 }
        divider.frame = NSRect(x: 14, y: y + 5, width: width - 28, height: 1)
        y += 9
        if let usageView {
            usageView.frame = NSRect(x: 0, y: y, width: width, height: 30)
            y += 30
        }
        urlButton.frame = NSRect(x: 6, y: y, width: width - 12, height: 26)
        settingsButton.frame = NSRect(x: 6, y: y + 26, width: width - 12, height: 26)
        y += 52
        quitDivider.frame = NSRect(x: 14, y: y + 4, width: width - 28, height: 1)
        y += 8
        quitButton.frame = NSRect(x: 6, y: y, width: width - 12, height: 26)
        let size = NSSize(width: width, height: y + 34)
        // Resize the popover before its view: otherwise AppKit can see matching view dimensions and
        // skip resizing the window, leaving the new Last Error clipped above the visible content.
        onResize(size)
        view.setFrameSize(size)
        preferredContentSize = size
        view.layoutSubtreeIfNeeded()
    }

    private func scroll(to y: CGFloat) {
        let maximum = max(0, table.bounds.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(maximum, max(0, y))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    @objc private func viewportChanged() {
        guard isBrowsing, !isUpdating else { return }
        let range = table.rows(in: scroll.documentVisibleRect)
        guard range.location != NSNotFound, range.length > 0 else {
            onVisibleEntries([])
            return
        }
        let end = min(entries.count, range.location + range.length + 2)
        onVisibleEntries(entries[range.location..<end].map(\.publicID))
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = table.makeView(withIdentifier: NSUserInterfaceItemIdentifier("HistoryEntry"), owner: self) as? HistoryRowView
            ?? HistoryRowView()
        let entry = entries[row]
        cell.configure(entry: entry, image: thumbnail(entry),
                       onCopy: { [weak self] in self?.onCopy(entry) },
                       onOpen: { [weak self] in self?.onOpen(entry) },
                       onDelete: { [weak self] in self?.onDelete(entry) },
                       onHover: { [weak self] in
                           guard let self, !isUpdating, let index = entries.firstIndex(where: { $0.publicID == entry.publicID }) else { return }
                           table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                       })
        cell.isHighlighted = table.selectedRow == row
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        HistoryTableRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if table.selectedRow >= 0 {
            for command in [urlButton, settingsButton, quitButton] { command.clearHover() }
        }
        updateHighlights()
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        entries[row].filename
    }

    private var selectedCell: HistoryRowView? {
        guard entries.indices.contains(table.selectedRow) else { return nil }
        return table.view(atColumn: 0, row: table.selectedRow, makeIfNecessary: true) as? HistoryRowView
    }

    private func updateKeyViews() {
        let controls: [NSView] = [table] + (selectedCell?.actionButtons ?? []) + [urlButton, settingsButton, quitButton]
        for (index, control) in controls.enumerated() {
            control.nextKeyView = controls[(index + 1) % controls.count]
        }
    }

    private func updateHighlights() {
        table.enumerateAvailableRowViews { rowView, row in
            (rowView.view(atColumn: 0) as? HistoryRowView)?.isHighlighted = row == self.table.selectedRow
        }
        if !isUpdating { updateKeyViews() }
    }

    private func copySelection() {
        if let hoveredCommand {
            hoveredCommand.performClick(nil)
            return
        }
        guard entries.indices.contains(table.selectedRow) else { return }
        onCopy(entries[table.selectedRow])
    }
}

@MainActor
private final class HistoryTableView: NSTableView {
    var onCopy: () -> Void = {}
    var onDismiss: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onCopy()
        case 53: onDismiss()
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { onDismiss() }
}

@MainActor
private final class PopoverView: NSView {
    var onCloudinaryURL: () -> Void = {}
    var onDismiss: () -> Void = {}
    override var isFlipped: Bool { true }
    override func cancelOperation(_ sender: Any?) { onDismiss() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "," {
            onCloudinaryURL()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// A full-width native button with the same icon and title insets as the Usage line.
@MainActor
private final class CommandButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    private let label: NSTextField
    private let shortcutLabel: NSTextField
    private let icon = NSImageView()
    private var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            updateColors()
            needsDisplay = true
            onHoverChanged(isHovered)
        }
    }
    var onClick: () -> Void = {}
    var onHoverChanged: (Bool) -> Void = { _ in }

    init(title: String, symbol: String? = nil, shortcut: String) {
        label = NSTextField(labelWithString: title)
        shortcutLabel = NSTextField(labelWithString: shortcut)
        super.init(frame: .zero)
        self.title = ""
        isBordered = false
        setAccessibilityLabel(title)
        label.font = NSFont.menuFont(ofSize: 0)
        shortcutLabel.font = NSFont.systemFont(ofSize: 11)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.alignment = .right
        if let symbol { icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        icon.contentTintColor = .labelColor
        for child in [icon, label, shortcutLabel] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        target = self
        action = #selector(click)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    func clearHover() { isHovered = false }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        updateColors()
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered || cell?.isHighlighted == true {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 0), xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }

    private func updateColors() {
        let highlighted = isHovered || cell?.isHighlighted == true
        label.textColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        shortcutLabel.textColor = highlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        icon.contentTintColor = highlighted ? .selectedMenuItemTextColor : .labelColor
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { performClick(nil) }
        else { super.keyDown(with: event) }
    }

    @objc private func click() { onClick() }
}
