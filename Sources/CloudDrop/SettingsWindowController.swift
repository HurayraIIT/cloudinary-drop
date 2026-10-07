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
        // Return in the field still sends this while a check is running.
        guard saveButton.isEnabled else { return }
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
                // Uploading is what matters, so a key that can't list or delete uploads is still saved, with a warning.
                let cannotList = await Self.cannotList(credentials)
                let cannotDelete = await Self.cannotDelete(credentials)
                if cannotList || cannotDelete {
                    statusLabel.stringValue = Self.warning(cannotList: cannotList, cannotDelete: cannotDelete)
                    saveButton.isEnabled = true
                    return
                }
                statusLabel.stringValue = "Saved."
                try? await Task.sleep(for: .seconds(1))
                close()
            } catch {
                statusLabel.stringValue = error.localizedDescription
            }
            saveButton.isEnabled = true
        }
    }

    private static func warning(cannotList: Bool, cannotDelete: Bool) -> String {
        switch (cannotList, cannotDelete) {
        case (true, true): "Saved. This key can upload but can't list or delete uploads, so the Link History will only show this Mac's uploads and Delete will fail."
        case (true, false): "Saved. This key can upload but can't list uploads, so the Link History will only show this Mac's uploads."
        default: "Saved. This key can upload but can't delete, so Delete will fail."
        }
    }

    /// Only a 403 counts, as for listing.
    private static func cannotDelete(_ credentials: CloudinaryCredentials) async -> Bool {
        do {
            try await Uploader.probeDeletePermission(credentials)
            return false
        } catch let error as DeleteError {
            if case .notAllowedToDelete = error {
                log.error("Saved key can't delete: \(String(describing: error), privacy: .public)")
                return true
            }
            return false
        } catch {
            return false
        }
    }

    /// Only a 403 counts: a network hiccup or the rate limit says nothing about the key.
    private static func cannotList(_ credentials: CloudinaryCredentials) async -> Bool {
        let search = HistorySearch(credentials: credentials)
        defer { search.invalidate() }
        do {
            _ = try await search.recentUploads(limit: 1)
            return false
        } catch let error as HistoryFetchError {
            if case .notAllowedToList = error {
                log.error("Saved key can't list uploads: \(String(describing: error), privacy: .public)")
                return true
            }
            return false
        } catch {
            return false
        }
    }
}
