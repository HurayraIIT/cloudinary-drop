import AppKit

/// The entire Last Error, wrapped to the menu's width instead of hiding its ending in a tooltip.
@MainActor
final class LastErrorRowView: NSView {
    init(message: String) {
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = NSFont.menuFont(ofSize: 0)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        let textWidth = HistoryRowView.width - 38 - 14
        label.preferredMaxLayoutWidth = textWidth
        let textHeight = ceil(label.cell!.cellSize(forBounds: NSRect(
            x: 0, y: 0, width: textWidth, height: .greatestFiniteMagnitude)).height)
        super.init(frame: NSRect(x: 0, y: 0, width: HistoryRowView.width, height: max(30, textHeight + 16)))
        autoresizingMask = .width
        setAccessibilityLabel("Last Error: \(message)")

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor
        for view in [icon, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 38),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.heightAnchor.constraint(equalToConstant: textHeight),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}
