import AppKit
import CloudDropCore
import OSLog
import UniformTypeIdentifiers

/// Watch with: log stream --predicate 'subsystem == "com.hurayraiit.clouddrop"'
let log = Logger(subsystem: "com.hurayraiit.clouddrop", category: "upload")

/// The Upload Queue: Media Files are uploaded one at a time, in the order they were dropped.
@MainActor
final class UploadQueue {
    enum Event { case changed, succeeded, failed }

    private struct Job {
        let fileURL: URL
        let filename: String
        let kind: MediaKind
        /// Files received from a file promise or external temporary drop live in a temporary folder
        /// and are removed after uploading, or preserved to Downloads if the upload is refused or fails.
        let isTemporary: Bool
    }

    private(set) var lastError: String?
    /// Progress of the current Upload, or nil when the queue is idle.
    private(set) var progress: Double?

    var onEvent: (Event) -> Void = { _ in }
    var credentials: () -> CloudinaryCredentials? = { nil }
    /// Each successful Upload, with its thumbnail for images, for the Link History.
    var onUploaded: (HistoryEntry, NSImage?) -> Void = { _, _ in }
    /// Each successful Delete, so the Link History can hide it.
    var onDeleted: (HistoryEntry) -> Void = { _ in }

    private var pending: [Job] = []
    private var isRunning = false
    /// Reused across Uploads so they share one URLSession and its connections.
    private var uploader: Uploader?
    /// Counts Uploads, so progress arriving late from a finished one is ignored.
    private var uploadNumber = 0

    /// A new Drop clears the Last Error from the previous one.
    func beginDrop() {
        lastError = nil
        onEvent(.changed)
    }

    func refuse(_ message: String) {
        log.error("Refused: \(message, privacy: .public)")
        lastError = message
        onEvent(.failed)
    }

    /// Checks a dropped file and queues it if it is a Media File within its Size Limit.
    func add(fileURL: URL, isTemporary: Bool = false) {
        let isTemp = isTemporary || TemporaryFiles.isTemporary(url: fileURL)
        let filename = fileURL.lastPathComponent
        let result: Result<MediaKind, Refusal>
        if let values = try? fileURL.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isDirectoryKey]) {
            let type = values.isDirectory == true ? nil : values.contentType
            result = checkMediaFile(filename: filename, type: type, byteCount: values.fileSize.map(Int64.init))
        } else {
            result = .failure(.unreadable(filename: filename))
        }

        switch result {
        case let .failure(refusal):
            if isTemp {
                TemporaryFiles.preserveTemporaryFile(at: fileURL, originalFilename: filename)
            }
            refuse(refusal.message)
        case let .success(kind):
            var uploadURL = fileURL
            if isTemp && !fileURL.path.contains(TemporaryFiles.dropsFolderName) {
                let folder = TemporaryFiles.dropFolder()
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = folder.appendingPathComponent(filename)
                if (try? FileManager.default.moveItem(at: fileURL, to: destination)) != nil {
                    uploadURL = destination
                } else if (try? FileManager.default.copyItem(at: fileURL, to: destination)) != nil {
                    uploadURL = destination
                }
            }
            pending.append(Job(fileURL: uploadURL, filename: filename, kind: kind, isTemporary: isTemp))
            startIfNeeded()
        }
    }

    /// Copies a Link History entry's Share Link again. The ✓ flash is the only sign it worked, as the menu has closed.
    func recopy(_ link: URL) {
        copyToClipboard(link)
        onEvent(.succeeded)
    }

    /// Deletes a Link History entry from Cloudinary. It runs at once, alongside any Upload, and like a Drop it
    /// clears the Last Error when it begins.
    func delete(_ entry: HistoryEntry) {
        guard let credentials = credentials() else {
            refuse("Set Cloudinary URL first")
            return
        }
        lastError = nil
        onEvent(.changed)
        log.info("Deleting \(entry.filename, privacy: .public) \(entry.publicID, privacy: .public)")
        let uploader = uploader(for: credentials)
        Task {
            do {
                let outcome = try await uploader.delete(publicID: entry.publicID, kind: entry.kind)
                log.info("Deleted \(entry.publicID, privacy: .public)\(outcome == .alreadyGone ? " (it was already gone)" : "", privacy: .public)")
                onDeleted(entry)
                onEvent(.succeeded)
            } catch {
                log.error("Delete failed for \(entry.publicID, privacy: .public): \(String(describing: error), privacy: .public)")
                lastError = "Couldn't delete \(entry.filename): \(error.localizedDescription)"
                onEvent(.failed)
            }
        }
    }

    private func startIfNeeded() {
        guard !isRunning, !pending.isEmpty else { return }
        isRunning = true
        Task { await drain() }
    }

    private func drain() async {
        while !pending.isEmpty {
            let job = pending.removeFirst()
            let succeeded = await upload(job)
            if job.isTemporary {
                if succeeded {
                    try? FileManager.default.removeItem(at: job.fileURL)
                } else {
                    TemporaryFiles.preserveTemporaryFile(at: job.fileURL, originalFilename: job.filename)
                }
            }
        }
        progress = nil
        isRunning = false
        onEvent(.changed)
    }

    @discardableResult
    private func upload(_ job: Job) async -> Bool {
        guard let credentials = credentials() else {
            refuse("Set Cloudinary URL first")
            return false
        }
        uploadNumber += 1
        let number = uploadNumber
        progress = 0
        onEvent(.changed)
        let publicID = PublicID.make()
        log.info("Uploading \(job.fileURL.path, privacy: .public) as \(job.kind.rawValue, privacy: .public) \(publicID, privacy: .public)")

        do {
            let file = try await uploader(for: credentials).upload(
                fileURL: job.fileURL,
                kind: job.kind,
                publicID: publicID,
                displayName: job.filename,
                progress: { [weak self] fraction in
                    Task { @MainActor in self?.report(progress: fraction, upload: number) }
                })
            let link = ShareLink.make(cloudName: credentials.cloudName, kind: job.kind, file: file)
            log.info("Uploaded \(job.filename, privacy: .public) -> \(link.absoluteString, privacy: .public)")
            copyToClipboard(link)
            NSWorkspace.shared.open(link)
            let thumbnail = job.kind == .image ? await Self.thumbnail(of: job.fileURL) : nil
            onUploaded(HistoryEntry(publicID: file.publicID, kind: job.kind, filename: job.filename,
                                    uploadedAt: file.createdAt ?? Date(), shareLink: link, byteCount: file.byteCount), thumbnail)
            progress = nil
            onEvent(.succeeded)
            return true
        } catch {
            log.error("Upload failed for \(job.filename, privacy: .public): \(String(describing: error), privacy: .public)")
            progress = nil
            lastError = "\(job.filename): \(error.localizedDescription)"
            onEvent(.failed)
            return false
        }
    }

    /// Made right after the Upload, while the file is still on disk: files received from a file promise
    /// are deleted next. Decoding happens off the main actor so the menu bar never stalls.
    private static func thumbnail(of fileURL: URL) async -> NSImage? {
        let side = HistoryRowView.thumbnailSide
        let image = await Task.detached { Thumbnail.make(imageAt: fileURL, side: Int(side * 2)) }.value
        return image.map { NSImage(cgImage: $0, size: NSSize(width: side, height: side)) }
    }

    /// Swaps in a new Uploader only when the Cloudinary URL has changed.
    private func uploader(for credentials: CloudinaryCredentials) -> Uploader {
        if let uploader, uploader.credentials == credentials { return uploader }
        uploader?.invalidate()
        let fresh = Uploader(credentials: credentials)
        uploader = fresh
        return fresh
    }

    private func report(progress fraction: Double, upload number: Int) {
        guard number == uploadNumber, let shown = progress else { return }
        progress = fraction
        // A large file reports progress thousands of times; redraw only when the percentage changes.
        if Int(fraction * 100) != Int(shown * 100) { onEvent(.changed) }
    }

    private func copyToClipboard(_ link: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.absoluteString, forType: .string)
    }
}
