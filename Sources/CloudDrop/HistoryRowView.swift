import AppKit
import CloudDropCore

/// Reused by the table, so retaining fifty entries does not create fifty sets of controls.
@MainActor
final class HistoryRowView: NSTableCellView {
    static let thumbnailSide: CGFloat = 28
    /// Keep the existing Cloudinary thumbnail size, avoiding another transformation for older Uploads.
    static let thumbnailPixels = 44
    static let width: CGFloat = 420
    static let height: CGFloat = 40
    static let columnFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .regular)

    private let thumbnail = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let details = NSTextField(labelWithString: "")
    private let copyButton = RowButton(symbol: "doc.on.doc", label: "Copy Share Link")
    private let openButton = RowButton(symbol: "arrow.up.right.square", label: "Open in Browser")
    private let deleteButton = RowButton(symbol: "trash", label: "Delete…")
    private var isPlaceholder = true
    private var onHover: () -> Void = {}
    private var onCopy: () -> Void = {}

    var isHighlighted = false { didSet { updateColors() } }
    var actionButtons: [NSButton] { [copyButton, openButton, deleteButton] }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        identifier = NSUserInterfaceItemIdentifier("HistoryEntry")
        title.font = NSFont.menuFont(ofSize: 0)
        title.lineBreakMode = .byTruncatingMiddle
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        details.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        thumbnail.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 4
        thumbnail.layer?.masksToBounds = true
        for view in [thumbnail, title, details, copyButton, openButton, deleteButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        for button in [copyButton, openButton, deleteButton] {
            button.widthAnchor.constraint(equalToConstant: 22).isActive = true
            button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            thumbnail.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: Self.thumbnailSide),
            thumbnail.heightAnchor.constraint(equalToConstant: Self.thumbnailSide),
            title.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 9),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            title.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8),
            details.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            details.topAnchor.constraint(equalTo: title.bottomAnchor),
            details.trailingAnchor.constraint(lessThanOrEqualTo: title.trailingAnchor),
            copyButton.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -4),
            openButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -10),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            copyButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            openButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(entry: HistoryEntry, image: NSImage?, onCopy: @escaping () -> Void,
                   onOpen: @escaping () -> Void, onDelete: @escaping () -> Void, onHover: @escaping () -> Void) {
        self.onHover = onHover
        self.onCopy = onCopy
        title.stringValue = entry.filename
        let size = entry.byteCount.map(MenuText.fileSize) ?? ""
        let time = HistoryTime.label(for: entry.uploadedAt)
        details.stringValue = [size, time].filter { !$0.isEmpty }.joined(separator: " · ")
        toolTip = ([entry.shareLink.absoluteString, HistoryTime.full(entry.uploadedAt)] + (size.isEmpty ? [] : [size]))
            .joined(separator: "\n")
        setAccessibilityLabel([entry.filename, size, time].filter { !$0.isEmpty }.joined(separator: ", "))
        copyButton.onClick = onCopy
        openButton.onClick = onOpen
        deleteButton.onClick = onDelete
        isPlaceholder = image == nil
        thumbnail.image = image ?? NSImage(systemSymbolName: entry.kind == .video ? "film" : "photo", accessibilityDescription: nil)
        updateColors()
    }

    func setThumbnail(_ image: NSImage) {
        isPlaceholder = false
        thumbnail.image = image
        thumbnail.contentTintColor = nil
    }

    override func mouseEntered(with event: NSEvent) { onHover() }

    // Labels share the row's click target; the three buttons keep their own actions.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit is NSButton ? hit : self
    }

    override func mouseDown(with event: NSEvent) { onHover() }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onCopy() }
    }

    private func updateColors() {
        title.textColor = isHighlighted ? .selectedMenuItemTextColor : .labelColor
        details.textColor = isHighlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        thumbnail.contentTintColor = isPlaceholder ? (isHighlighted ? .selectedMenuItemTextColor : .secondaryLabelColor) : nil
        for button in [copyButton, openButton, deleteButton] { button.isRowHighlighted = isHighlighted }
    }
}

@MainActor
final class HistoryTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}

@MainActor
private final class RowButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    var isRowHighlighted = false { didSet { updateTint() } }
    private var isHovered = false { didSet { updateTint() } }
    var onClick: () -> Void = {}

    init(symbol: String, label: String) {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        isBordered = false
        imagePosition = .imageOnly
        toolTip = label
        setAccessibilityLabel(label)
        target = self
        action = #selector(click)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        updateTint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 22, height: 26) }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    @objc private func click() { onClick() }

    private func updateTint() {
        contentTintColor = isRowHighlighted ? .selectedMenuItemTextColor : (isHovered ? .controlAccentColor : .secondaryLabelColor)
    }
}
