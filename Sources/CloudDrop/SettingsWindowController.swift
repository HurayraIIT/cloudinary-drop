import AppKit
import CloudDropCore

/// The one-field window where the Cloudinary URL is pasted, checked and saved.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let field = NSSecureTextField()
    private let currentLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let onSaved: (CloudinaryCredentials) -> Void

    init(onSaved: @escaping (CloudinaryCredentials) -> Void) {
        self.onSaved = onSaved
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 170),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "CloudDrop"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        layout(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func show(current: CloudinaryCredentials?) {
        currentLabel.stringValue = current.map { "Current cloud: \($0.cloudName)" } ?? "No Cloudinary URL saved yet."
        statusLabel.stringValue = ""
        field.stringValue = ""
        saveButton.isEnabled = true
        NSApp.activate()
        window?.center()
        showWindow(nil)
        window?.makeFirstResponder(field)
    }

    private func layout(in window: NSWindow) {
        let prompt = NSTextField(labelWithString: "Paste your Cloudinary URL (cloudinary://key:secret@cloud):")
        field.placeholderString = "cloudinary://…"
        field.target = self
        field.action = #selector(save)
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"
        currentLabel.textColor = .secondaryLabelColor
        statusLabel.textColor = .secondaryLabelColor

        let buttons = NSStackView(views: [statusLabel, saveButton])
        buttons.distribution = .fill
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [currentLabel, prompt, field, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        window.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
            field.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
    }

    @objc private func save() {
        guard let credentials = CloudinaryCredentials(parsing: field.stringValue) else {
            statusLabel.stringValue = "That doesn't look like cloudinary://key:secret@cloud"
            return
        }
        saveButton.isEnabled = false
        statusLabel.stringValue = "Checking with Cloudinary…"

        Task {
            do {
                try await Uploader.verify(credentials)
                try KeychainStore.save(credentials)
                onSaved(credentials)
                currentLabel.stringValue = "Current cloud: \(credentials.cloudName)"
                field.stringValue = ""
                statusLabel.stringValue = "Saved."
                try? await Task.sleep(for: .seconds(1))
                close()
            } catch {
                statusLabel.stringValue = error.localizedDescription
            }
            saveButton.isEnabled = true
        }
    }
}
