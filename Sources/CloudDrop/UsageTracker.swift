import Foundation
import CloudDropCore

/// The menu's Usage line: the whole account's counts, stored bytes and credits. Its calls share the Admin API's
/// 500 an hour with the Link History and the other Mac, so it refreshes far less often. Nothing is written to disk.
@MainActor
final class UsageTracker {
    /// Cloudinary updates the stored bytes and credits once a day.
    private static let storageInterval: TimeInterval = 60 * 60
    private static let countsInterval: TimeInterval = 5 * 60

    private(set) var usage = Usage()

    var credentials: () -> CloudinaryCredentials? = { nil }
    /// True while the Link History is paused by a rate limit: the same limit applies here.
    var isPaused: () -> Bool = { false }
    var onRateLimited: (Date?) -> Void = { _ in }
    var onChange: () -> Void = {}

    private var storage = UsageSchedule(interval: storageInterval)
    private var counts = UsageSchedule(interval: countsInterval)
    /// When this Mac last uploaded or deleted something, so the counts are refreshed sooner.
    private var countsChangedAt: Date?
    /// Bumped when the Cloudinary URL changes, so a fetch for the old one is ignored.
    private var generation = 0
    private var reader: UsageReader?

    /// Fetches whichever half is due, unless a rate limit is in force.
    func refresh() {
        guard !isPaused(), let credentials = credentials() else { return }
        let now = Date()
        let reader = reader(for: credentials)
        let generation = generation

        if storage.isDue(at: now) {
            storage.isFetching = true
            storage.lastTry = now
            Task {
                let result: Result<Usage, any Error>
                do { result = .success(try await reader.storage()) } catch { result = .failure(error) }
                guard generation == self.generation else { return }
                storage.isFetching = false
                if let answer = settle(result, what: "stored bytes") {
                    storage.lastAnswer = now
                    usage.storedBytes = answer?.storedBytes
                    usage.creditsUsedPercent = answer?.creditsUsedPercent
                }
                onChange()
            }
        }

        if counts.isDue(at: now, changedAt: countsChangedAt) {
            counts.isFetching = true
            counts.lastTry = now
            Task {
                let result: Result<(images: Int, videos: Int), any Error>
                do {
                    async let images = reader.count(of: .image)
                    async let videos = reader.count(of: .video)
                    result = .success(try await (images, videos))
                } catch {
                    result = .failure(error)
                }
                guard generation == self.generation else { return }
                counts.isFetching = false
                if let answer = settle(result, what: "counts") {
                    counts.lastAnswer = now
                    usage.images = answer?.images
                    usage.videos = answer?.videos
                }
                onChange()
            }
        }
    }

    /// This Mac uploaded or deleted something, so the counts are out of date.
    func countsChanged() {
        countsChangedAt = Date()
    }

    /// Starts over after the Cloudinary URL changes: the old Usage may belong to another cloud.
    func reset() {
        generation += 1
        reader?.invalidate()
        reader = nil
        usage = Usage()
        storage = UsageSchedule(interval: Self.storageInterval)
        counts = UsageSchedule(interval: Self.countsInterval)
        countsChangedAt = nil
        onChange()
        refresh()
    }

    /// What to keep from a fetch: the values on success, nil when the key may not read them (which hides the line
    /// until the next interval), and nothing at all on any other failure, which keeps the last values and is only logged.
    private func settle<Value>(_ result: Result<Value, any Error>, what: String) -> Value?? {
        switch result {
        case let .success(value):
            return value
        case let .failure(HistoryFetchError.rateLimited(until)):
            log.error("Usage \(what, privacy: .public) paused: \(String(describing: HistoryFetchError.rateLimited(until: until)), privacy: .public)")
            onRateLimited(until)
        case let .failure(error as HistoryFetchError):
            log.error("Usage \(what, privacy: .public) refresh failed: \(String(describing: error), privacy: .public)")
            if case .notAllowedToList = error { return .some(nil) }
        case let .failure(error):
            log.error("Usage \(what, privacy: .public) refresh failed: \(String(describing: error), privacy: .public)")
        }
        return nil
    }

    /// Swaps in a new UsageReader only when the Cloudinary URL has changed.
    private func reader(for credentials: CloudinaryCredentials) -> UsageReader {
        if let reader, reader.credentials == credentials { return reader }
        reader?.invalidate()
        let fresh = UsageReader(credentials: credentials)
        reader = fresh
        return fresh
    }
}
