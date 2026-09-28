import AppKit

/// One Link History entry in the menu: thumbnail, filename · time, and Copy / Open buttons.
/// A view in a menu item draws its own highlight; `StatusController` sets `isHighlighted`
/// from `menu(_:willHighlight:)` so hover and arrow keys look like a normal menu item.
@MainActor
final class HistoryRowView: NSView {
    static let thumbnailSide: CGFloat = 22

    var isHighlighted = false {
        didSet {
            guard isHighlighted != oldValue else { return }
            updateColors()
            needsDisplay = true
        }
    }

    private let thumbnail = NSImageView()
    private let isPlaceholder: Bool
    private let title: NSTextField
    private let time: NSTextField
    private let copyButton: RowButton
    private let openButton: RowButton
    private let onCopy: () -> Void

    init(entry: HistoryEntry, time timeText: String, onCopy: @escaping () -> Void, onOpen: @escaping () -> Void) {
        self.onCopy = onCopy
        isPlaceholder = entry.thumbnail == nil
        title = NSTextField(labelWithString: entry.filename)
        time = NSTextField(labelWithString: "· \(timeText)")
        copyButton = RowButton(symbol: "doc.on.doc", label: "Copy Link", action: onCopy)
        openButton = RowButton(symbol: "arrow.up.right.square", label: "Open in Browser", action: onOpen)
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 30))
        autoresizingMask = .width
        toolTip = entry.link.absoluteString
        setAccessibilityLabel("\(entry.filename), \(timeText)")

        if let image = entry.thumbnail {
            thumbnail.image = image
            thumbnail.imageScaling = .scaleProportionallyUpOrDown
            thumbnail.wantsLayer = true
            thumbnail.layer?.cornerRadius = 4
            thumbnail.layer?.masksToBounds = true
        } else {
            thumbnail.image = NSImage(systemSymbolName: entry.kind == .video ? "film" : "photo", accessibilityDescription: nil)
            thumbnail.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        }

        let font = NSFont.menuFont(ofSize: 0)
        title.font = font
        title.lineBreakMode = .byTruncatingMiddle
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        time.font = font
        time.setContentCompressionResistancePriority(.required, for: .horizontal)

        for view in [thumbnail, title, time, copyButton, openButton] as [NSView] {
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
            time.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 4),
            time.centerYAnchor.constraint(equalTo: centerYAnchor),
            time.trailingAnchor.constraint(lessThanOrEqualTo: copyButton.leadingAnchor, constant: -10),
            copyButton.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -4),
            copyButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            openButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            openButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

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
        time.textColor = isHighlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        if isPlaceholder {
            thumbnail.contentTintColor = isHighlighted ? .selectedMenuItemTextColor : .secondaryLabelColor
        }
        copyButton.isRowHighlighted = isHighlighted
        openButton.isRowHighlighted = isHighlighted
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
