import AppKit

/// The Usage line in the fixed footer. It uses the filenames' font and color, and never highlights.
@MainActor
final class UsageRowView: NSView {
    init(line: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: HistoryRowView.width, height: 30))
        autoresizingMask = .width
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "chart.bar", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        icon.contentTintColor = .labelColor
        let label = NSTextField(labelWithString: line)
        label.font = HistoryRowView.columnFont
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        addSubview(label)
        setAccessibilityLabel(line)
        // Match the native menu's image and title columns. NSTextField's alignment rect adds 2 pt to the title inset.
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 38),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}
