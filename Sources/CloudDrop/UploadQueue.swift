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

    /// Where a Job's file came from, which decides what happens to it once it's uploaded or refused.
    private enum Origin {
        /// A file of the user's, e.g. from Finder. It's never moved or deleted.
        case userFile
        /// Received from a file promise into a Drop folder. It's deleted afterwards, whatever happened.
        case received
        /// A Capture, the only copy. It's deleted once uploaded, and saved to Downloads otherwise.
        case capture
    }

    private struct Job {
        let fileURL: URL
        let filename: String
        let kind: MediaKind
        let origin: Origin
    }

    private(set) var lastError: String?
    /// Progress of the current Upload, or nil when the queue is idle.
    private(set) var progress: Double?

    var onEvent: (Event) -> Void = { _ in }
    var credentials: () throws -> CloudinaryCredentials = { throw CredentialsError.notSet }
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
    /// `received` marks a file received from a file promise.
    func add(fileURL: URL, received: Bool = false) {
        let origin: Origin = TemporaryFiles.isCapture(fileURL) ? .capture : received ? .received : .userFile
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
            refuse(discard(fileURL, origin: origin, filename: filename, message: refusal.message))
        case let .success(kind):
            let uploadURL = origin == .capture ? Self.keep(capture: fileURL, filename: filename) : fileURL
            pending.append(Job(fileURL: uploadURL, filename: filename, kind: kind, origin: origin))
            startIfNeeded()
        }
    }

    /// Moves a Capture out of `TemporaryItems` straight away, because macOS deletes it when the drag ends.
    /// If that fails it's uploaded from where it is, while it lasts.
    private static func keep(capture fileURL: URL, filename: String) -> URL {
        let folder = TemporaryFiles.captureFolder()
        let destination = folder.appendingPathComponent(filename)
        let fileManager = FileManager.default
        guard (try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
              (try? fileManager.moveItem(at: fileURL, to: destination)) != nil
                || (try? fileManager.copyItem(at: fileURL, to: destination)) != nil
        else { return fileURL }
        return destination
    }

    /// Clears away a file that won't be uploaded, and returns the Last Error `message`, saying so when
    /// a Capture was saved to Downloads.
    private func discard(_ fileURL: URL, origin: Origin, filename: String, message: String) -> String {
        switch origin {
        case .userFile:
            return message
        case .received:
            TemporaryFiles.remove(fileURL)
            return message
        case .capture:
            guard let saved = TemporaryFiles.saveCaptureToDownloads(fileURL, filename: filename) else {
                log.error("Couldn't save the Capture \(filename, privacy: .public) to Downloads")
                return message
            }
            log.info("Saved the Capture \(filename, privacy: .public) to \(saved.path, privacy: .public)")
            return TemporaryFiles.mentioningCaptureSaved(message)
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
        let credentials: CloudinaryCredentials
        do {
            credentials = try self.credentials()
        } catch {
            refuse(error.localizedDescription)
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
            do {
                try await upload(job)
                if job.origin != .userFile { TemporaryFiles.remove(job.fileURL) }
            } catch {
                log.error("Upload failed for \(job.filename, privacy: .public): \(String(describing: error), privacy: .public)")
                progress = nil
                lastError = discard(job.fileURL, origin: job.origin, filename: job.filename,
                                    message: "\(job.filename): \(error.localizedDescription)")
                onEvent(.failed)
            }
        }
        progress = nil
        isRunning = false
        onEvent(.changed)
    }

    private func upload(_ job: Job) async throws {
        let credentials = try credentials()
        uploadNumber += 1
        let number = uploadNumber
        progress = 0
        onEvent(.changed)
        let publicID = PublicID.make()
        log.info("Uploading \(job.fileURL.path, privacy: .public) as \(job.kind.rawValue, privacy: .public) \(publicID, privacy: .public)")

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
    }

    /// Made right after the Upload, while the file is still on disk: received files and Captures
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
