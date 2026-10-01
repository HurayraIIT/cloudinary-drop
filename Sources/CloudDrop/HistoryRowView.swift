import AppKit
import CloudDropCore

/// One Link History entry in the menu: thumbnail, filename, size and time columns, and Copy / Open / Delete buttons.
/// A view in a menu item draws its own highlight; `StatusController` sets `isHighlighted`
/// from `menu(_:willHighlight:)` so hover and arrow keys look like a normal menu item.
@MainActor
final class HistoryRowView: NSView {
    static let thumbnailSide: CGFloat = 22
    static let width: CGFloat = 420
    /// Monospaced digits so times and sizes line up from row to row.
    static let columnFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .regular)

    /// The width of a column: its widest label among the rows in the menu, so every row lines up.
    static func columnWidth(_ labels: [String]) -> CGFloat {
        let field = NSTextField(labelWithString: "")
        field.font = columnFont
        return labels.map { label in
            field.stringValue = label
            return label.isEmpty ? 0 : field.intrinsicContentSize.width.rounded(.up)
        }.max() ?? 0
    }

    var isHighlighted = false {
        didSet {
            guard isHighlighted != oldValue else { return }
            updateColors()
            needsDisplay = true
        }
    }

    private let thumbnail = NSImageView()
    private var isPlaceholder = true
    private let title: NSTextField
    private let size: NSTextField
    private let time: NSTextField
    private let copyButton: RowButton
    private let openButton: RowButton
    private let deleteButton: RowButton
    private let onCopy: () -> Void

    /// `sizeText` is empty when Cloudinary didn't report a size; the cell stays blank rather than claim one.
    init(entry: HistoryEntry, thumbnail image: NSImage?, size sizeText: String, time timeText: String, fullTime: String,
         sizeWidth: CGFloat, timeWidth: CGFloat, onCopy: @escaping () -> Void, onOpen: @escaping () -> Void,
         onDelete: @escaping () -> Void) {
        self.onCopy = onCopy
        title = NSTextField(labelWithString: entry.filename)
        size = NSTextField(labelWithString: sizeText)
        time = NSTextField(labelWithString: timeText)
        copyButton = RowButton(symbol: "doc.on.doc", label: "Copy Link", action: onCopy)
        openButton = RowButton(symbol: "arrow.up.right.square", label: "Open in Browser", action: onOpen)
        deleteButton = RowButton(symbol: "trash", label: "Delete…", action: onDelete)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 30))
        autoresizingMask = .width
        let details = sizeText.isEmpty ? fullTime : "\(fullTime) · \(sizeText)"
        toolTip = "\(entry.shareLink.absoluteString)\n\(details)"
        setAccessibilityLabel([entry.filename, sizeText, timeText].filter { !$0.isEmpty }.joined(separator: ", "))

        if let image {
            setThumbnail(image)
        } else {
            thumbnail.image = NSImage(systemSymbolName: entry.kind == .video ? "film" : "photo", accessibilityDescription: nil)
            thumbnail.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        }

        title.font = NSFont.menuFont(ofSize: 0)
        title.lineBreakMode = .byTruncatingMiddle
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        for column in [size, time] {
            column.font = Self.columnFont
            column.alignment = .right
        }

        for view in [thumbnail, title, size, time, copyButton, openButton, deleteButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            thumbnail.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: Self.thumbnailSide),
            thumbnail.heightAnchor.constraint(equalToConstant: Self.thumbnailSide),
            title.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: size.leadingAnchor, constant: -10),
            size.widthAnchor.constraint(equalToConstant: sizeWidth),
            size.trailingAnchor.constraint(equalTo: time.leadingAnchor, constant: sizeWidth > 0 ? -10 : 0),
            size.centerYAnchor.constraint(equalTo: centerYAnchor),
            time.widthAnchor.constraint(equalToConstant: timeWidth),
            time.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -10),
            time.centerYAnchor.constraint(equalTo: centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -4),
            copyButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            // A wider gap, so a slip off Open doesn't land on Delete.
            openButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -10),
            openButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Also called when a thumbnail from Cloudinary arrives while the menu is open.
    func setThumbnail(_ image: NSImage) {
        isPlaceholder = false
        thumbnail.image = image
        thumbnail.contentTintColor = nil
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 4
        thumbnail.layer?.masksToBounds = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 6, yRadius: 6).fill()
    }

    // Swallow the press so the click lands here, then copy on release like a menu item.
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        onCopy()
    }

    private func updateColors() {
        title.textColor = isHighlighted ? .selectedMenuItemTextColor : .labelColor
        for column in [size, time] {
            column.textColor = isHighlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        }
        if isPlaceholder {
            thumbnail.contentTintColor = isHighlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        }
        copyButton.isRowHighlighted = isHighlighted
        openButton.isRowHighlighted = isHighlighted
        deleteButton.isRowHighlighted = isHighlighted
    }
}

/// A borderless SF Symbol button that brightens under the mouse.
@MainActor
private final class RowButton: NSButton {
    var isRowHighlighted = false { didSet { updateTint() } }
    private var isHovered = false { didSet { updateTint() } }
    private let onClick: () -> Void

    init(symbol: String, label: String, action: @escaping () -> Void) {
        onClick = action
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        isBordered = false
        imagePosition = .imageOnly
        toolTip = label
        setAccessibilityLabel(label)
        target = self
        self.action = #selector(click)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        updateTint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 22, height: 22) }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    @objc private func click() { onClick() }

    /// On the blue highlight an accent-coloured icon would vanish, so there hover means full white.
    private func updateTint() {
        contentTintColor = switch (isRowHighlighted, isHovered) {
        case (true, true): .selectedMenuItemTextColor
        case (true, false): .selectedMenuItemTextColor.withAlphaComponent(0.7)
        case (false, true): .controlAccentColor
        case (false, false): .secondaryLabelColor
        }
    }
}
