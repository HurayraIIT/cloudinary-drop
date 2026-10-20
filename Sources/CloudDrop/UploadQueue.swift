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

    /// What the job at the front of the queue is doing, with its fraction done.
    enum Activity: Equatable {
        /// Nil when the video's length is unknown, so there's no percentage.
        case compressing(Double?)
        case uploading(Double)

        var percent: Int? {
            switch self {
            case let .compressing(fraction): fraction.map { Int($0 * 100) }
            case let .uploading(fraction): Int(fraction * 100)
            }
        }
    }

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
        /// Read when the file was dropped.
        let compression: CompressionSetting
    }

    private(set) var lastError: String?
    /// Nil when the queue is idle.
    private(set) var activity: Activity?

    var onEvent: (Event) -> Void = { _ in }
    var credentials: () throws -> CloudinaryCredentials = { throw CredentialsError.notSet }
    /// The menu's Compress Videos setting, and whether ffmpeg is installed.
    var compression: () -> CompressionSetting = { .off }
    /// Each successful Upload, with its thumbnail for images, for the Link History.
    var onUploaded: (HistoryEntry, NSImage?) -> Void = { _, _ in }
    /// Each successful Delete, so the Link History can hide it.
    var onDeleted: (HistoryEntry) -> Void = { _ in }

    private var pending: [Job] = []
    private var isRunning = false
    private var drainTask: Task<Void, Never>?
    /// Reused across Uploads so they share one URLSession and its connections.
    private var uploader: Uploader?
    /// Counts compressions and Uploads, so progress arriving late from a finished one is ignored.
    private var stepNumber = 0

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
        let compression = compression()
        let result: Result<MediaKind, Refusal>
        if let values = try? fileURL.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isDirectoryKey]) {
            let type = values.isDirectory == true ? nil : values.contentType
            result = checkMediaFile(filename: filename, type: type, byteCount: values.fileSize.map(Int64.init),
                                    compressingVideos: compression.isOn)
        } else {
            result = .failure(.unreadable(filename: filename))
        }

        switch result {
        case let .failure(refusal):
            refuse(discard(fileURL, origin: origin, filename: filename, message: refusal.message(compression: compression)))
        case let .success(kind):
            let uploadURL = origin == .capture ? Self.keep(capture: fileURL, filename: filename) : fileURL
            pending.append(Job(fileURL: uploadURL, filename: filename, kind: kind, origin: origin, compression: compression))
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
    /// a Capture was saved to Downloads, as `cd-<filename>`.
    private func discard(_ fileURL: URL, origin: Origin, filename: String, message: String) -> String {
        switch origin {
        case .userFile:
            return message
        case .received:
            TemporaryFiles.remove(fileURL)
            return message
        case .capture:
            return Self.saveToDownloads(fileURL, as: filename) ? TemporaryFiles.mentioningCaptureSaved(message) : message
        }
    }

    /// Moves a file that won't be uploaded to Downloads as `cd-<filename>`, and logs where it went.
    private static func saveToDownloads(_ fileURL: URL, as filename: String) -> Bool {
        guard let saved = TemporaryFiles.saveToDownloads(fileURL, filename: filename) else {
            log.error("Couldn't save \(filename, privacy: .public) to Downloads")
            return false
        }
        log.info("Saved \(filename, privacy: .public) to \(saved.path, privacy: .public)")
        return true
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
        drainTask = Task { await drain() }
    }

    /// Stops a running compression at quit, so ffmpeg doesn't keep running after CloudDrop has gone.
    /// Its partial output and any Capture still waiting are handled by the sweep at quit.
    func stop() {
        drainTask?.cancel()
    }

    private func drain() async {
        while !pending.isEmpty, !Task.isCancelled {
            let job = pending.removeFirst()
            if job.kind == .video, case let .on(quality) = job.compression {
                await compressAndUpload(job, quality: quality)
            } else {
                await uploadOriginal(job)
            }
        }
        activity = nil
        isRunning = false
        onEvent(.changed)
    }

    /// `note` becomes the Last Error once the Upload has succeeded.
    private func uploadOriginal(_ job: Job, note: String? = nil) async {
        do {
            try await upload(job.fileURL, as: job.filename, of: job)
            if job.origin != .userFile { TemporaryFiles.remove(job.fileURL) }
            if let note { lastError = note }
        } catch {
            fail(job, error)
        }
    }

    /// Every video is compressed while Compression is on, and the compressed file is uploaded even when it's
    /// bigger than the original, so its Share Link always plays in a browser (ADR 0008).
    private func compressAndUpload(_ job: Job, quality: QualityLevel) async {
        let output = TemporaryFiles.compressedVideo()
        defer { TemporaryFiles.remove(output) }
        stepNumber += 1
        let number = stepNumber
        activity = .compressing(nil)
        onEvent(.changed)
        log.info("Compressing \(job.fileURL.path, privacy: .public) at CRF \(quality.rawValue, privacy: .public)")
        do {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await Compressor.compress(job.fileURL, to: output, quality: quality) { [weak self] fraction in
                Task { @MainActor in self?.report(.compressing(fraction), step: number) }
            }
        } catch is CancellationError {
            return
        } catch {
            log.error("Couldn't compress \(job.filename, privacy: .public): \(String(describing: error), privacy: .public)")
            return await uploadUncompressed(job)
        }

        let byteCount = Self.byteCount(of: output)
        log.info("Compressed \(job.filename, privacy: .public) from \(Self.byteCount(of: job.fileURL) ?? -1, privacy: .public) to \(byteCount ?? -1, privacy: .public) bytes")
        guard let byteCount, byteCount <= MediaKind.video.sizeLimit else {
            return refuseCompressed(job, output: output, byteCount: byteCount, quality: quality)
        }
        do {
            try await upload(output, as: Compression.compressedFilename(job.filename), of: job)
            if job.origin != .userFile { TemporaryFiles.remove(job.fileURL) }
        } catch {
            fail(job, error)
        }
    }

    /// ffmpeg failed, so the original is uploaded if it fits the Size Limit, and refused as usual otherwise.
    private func uploadUncompressed(_ job: Job) async {
        activity = nil
        let byteCount = Self.byteCount(of: job.fileURL)
        guard let byteCount, byteCount <= MediaKind.video.sizeLimit else {
            let refusal = byteCount.map { Refusal.tooLarge(filename: job.filename, kind: .video, byteCount: $0) }
                ?? .unreadable(filename: job.filename)
            let message = addingSentence(Compression.failedHint, to: refusal.message)
            let savedName = Compression.downloadsName(job.filename, compressed: false)
            return refuse(discard(job.fileURL, origin: job.origin, filename: savedName, message: message))
        }
        await uploadOriginal(job, note: Compression.uploadedUncompressedMessage(filename: job.filename))
    }

    /// Still over the Size Limit: the compressed file goes to Downloads, and a Capture's original too, since
    /// it's the only copy. A file of the user's stays where it is.
    private func refuseCompressed(_ job: Job, output: URL, byteCount: Int64?, quality: QualityLevel) {
        activity = nil
        var saved = false
        if job.origin == .capture {
            saved = Self.saveToDownloads(job.fileURL, as: Compression.downloadsName(job.filename, compressed: false))
        } else if job.origin == .received {
            TemporaryFiles.remove(job.fileURL)
        }
        if Self.saveToDownloads(output, as: Compression.downloadsName(job.filename, compressed: true)) { saved = true }
        let refusal = byteCount.map { Refusal.stillTooLarge(filename: job.filename, byteCount: $0, quality: quality) }
            ?? .unreadable(filename: job.filename)
        refuse(saved ? TemporaryFiles.mentioningCaptureSaved(refusal.message) : refusal.message)
    }

    private func fail(_ job: Job, _ error: any Error) {
        log.error("Upload failed for \(job.filename, privacy: .public): \(String(describing: error), privacy: .public)")
        activity = nil
        lastError = discard(job.fileURL, origin: job.origin, filename: job.filename,
                            message: "\(job.filename): \(error.localizedDescription)")
        onEvent(.failed)
    }

    private static func byteCount(of fileURL: URL) -> Int64? {
        (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
    }

    /// Uploads `fileURL`, the dropped file or its compressed video, under `filename`.
    private func upload(_ fileURL: URL, as filename: String, of job: Job) async throws {
        let credentials = try credentials()
        stepNumber += 1
        let number = stepNumber
        activity = .uploading(0)
        onEvent(.changed)
        let publicID = PublicID.make()
        log.info("Uploading \(fileURL.path, privacy: .public) as \(job.kind.rawValue, privacy: .public) \(publicID, privacy: .public)")

        let file = try await uploader(for: credentials).upload(
            fileURL: fileURL,
            kind: job.kind,
            publicID: publicID,
            displayName: filename,
            progress: { [weak self] fraction in
                Task { @MainActor in self?.report(.uploading(fraction), step: number) }
            })
        let link = ShareLink.make(cloudName: credentials.cloudName, kind: job.kind, file: file)
        log.info("Uploaded \(filename, privacy: .public) -> \(link.absoluteString, privacy: .public)")
        copyToClipboard(link)
        NSWorkspace.shared.open(link)
        let thumbnail = job.kind == .image ? await Self.thumbnail(of: fileURL) : nil
        onUploaded(HistoryEntry(publicID: file.publicID, kind: job.kind, filename: filename,
                                uploadedAt: file.createdAt ?? Date(), shareLink: link, byteCount: file.byteCount), thumbnail)
        activity = nil
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

    private func report(_ update: Activity, step number: Int) {
        guard number == stepNumber, let shown = activity else { return }
        activity = update
        // A large file reports progress thousands of times; redraw only when the percentage changes.
        if update.percent != shown.percent { onEvent(.changed) }
    }

    private func copyToClipboard(_ link: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.absoluteString, forType: .string)
    }
}
