import AppKit

/// The Usage line in the menu. A view rather than a disabled item's title, which macOS draws dimmed and smaller than
/// the Link History's filenames. It never highlights: its menu item is disabled, so it gets no hover or arrow keys.
@MainActor
final class UsageRowView: NSView {
    init(line: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: HistoryRowView.width, height: 30))
        autoresizingMask = .width
        let label = NSTextField(labelWithString: line)
        label.font = HistoryRowView.columnFont
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        // Lines up with standard menu item titles below (Set Cloudinary URL… and Settings): 14 pt, as no top-level
        // item has a checkmark to make room for. NSTextField has 2 pt alignment rect insets, so the constant is +2.
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}
