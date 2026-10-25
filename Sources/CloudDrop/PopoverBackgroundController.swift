import AppKit

/// Paints the entire popover, including its rounded edges and arrow, without a translucent material.
@MainActor
final class PopoverBackgroundController: NSViewController {
    private let content: NSViewController

    init(content: NSViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let background = PopoverBackgroundView(frame: content.view.frame)
        view = background
        addChild(content)
        let body = content.view
        body.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: background.safeAreaLayoutGuide.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: background.safeAreaLayoutGuide.trailingAnchor),
            body.topAnchor.constraint(equalTo: background.safeAreaLayoutGuide.topAnchor),
            body.bottomAnchor.constraint(equalTo: background.safeAreaLayoutGuide.bottomAnchor),
        ])
    }
}

@MainActor
private final class PopoverBackgroundView: NSView {
    override var isOpaque: Bool { true }
    override var allowsVibrancy: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(1).setFill()
        bounds.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
