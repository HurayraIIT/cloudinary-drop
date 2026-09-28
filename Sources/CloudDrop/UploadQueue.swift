import AppKit
import CloudDropCore
import OSLog
import UniformTypeIdentifiers

/// Watch with: log stream --predicate 'subsystem == "com.hurayraiit.clouddrop"'
let log = Logger(subsystem: "com.hurayraiit.clouddrop", category: "upload")

/// One entry in the Link History.
struct HistoryEntry {
    let filename: String
    let uploadedAt: Date
    let link: URL
}

/// The Upload Queue: Media Files are uploaded one at a time, in the order they were dropped.
@MainActor
final class UploadQueue {
    enum Event { case changed, succeeded, failed }

    private struct Job {
        let fileURL: URL
        let filename: String
        let kind: MediaKind
        /// Files received from a file promise live in a temporary folder and are removed after uploading.
        let isTemporary: Bool
    }

    static let historyLimit = 10

    private(set) var history: [HistoryEntry] = []
    private(set) var lastError: String?
    /// Progress of the current Upload, or nil when the queue is idle.
    private(set) var progress: Double?

    var onEvent: (Event) -> Void = { _ in }
    var credentials: () -> CloudinaryCredentials? = { nil }

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
            if isTemporary { try? FileManager.default.removeItem(at: fileURL) }
            refuse(refusal.message)
        case let .success(kind):
            pending.append(Job(fileURL: fileURL, filename: filename, kind: kind, isTemporary: isTemporary))
            startIfNeeded()
        }
    }

    func recopy(_ entry: HistoryEntry) {
        copyToClipboard(entry.link)
    }

    private func startIfNeeded() {
        guard !isRunning, !pending.isEmpty else { return }
        isRunning = true
        Task { await drain() }
    }

    private func drain() async {
        while !pending.isEmpty {
            let job = pending.removeFirst()
            await upload(job)
            if job.isTemporary { try? FileManager.default.removeItem(at: job.fileURL) }
        }
        progress = nil
        isRunning = false
        onEvent(.changed)
    }

    private func upload(_ job: Job) async {
        guard let credentials = credentials() else {
            refuse("Set Cloudinary URL first")
            return
        }
        uploadNumber += 1
        let number = uploadNumber
        progress = 0
        onEvent(.changed)
        let publicID = PublicID.make(originalFilename: job.filename)
        log.info("Uploading \(job.fileURL.path, privacy: .public) as \(job.kind.rawValue, privacy: .public) \(publicID, privacy: .public)")

        do {
            let secureURL = try await uploader(for: credentials).upload(
                fileURL: job.fileURL,
                kind: job.kind,
                publicID: publicID,
                progress: { [weak self] fraction in
                    Task { @MainActor in self?.report(progress: fraction, upload: number) }
                })
            let link = ShareLink.make(secureURL: secureURL)
            log.info("Uploaded \(job.filename, privacy: .public) -> \(link.absoluteString, privacy: .public)")
            copyToClipboard(link)
            NSWorkspace.shared.open(link)
            history.insert(HistoryEntry(filename: job.filename, uploadedAt: Date(), link: link), at: 0)
            history = Array(history.prefix(Self.historyLimit))
            progress = nil
            onEvent(.succeeded)
        } catch {
            log.error("Upload failed for \(job.filename, privacy: .public): \(String(describing: error), privacy: .public)")
            progress = nil
            lastError = "\(job.filename): \(error.localizedDescription)"
            onEvent(.failed)
        }
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
