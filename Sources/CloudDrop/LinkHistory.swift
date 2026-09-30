import AppKit
import CloudDropCore

/// The Link History: the newest Uploads in the account, from either Mac (ADR 0006). The menu shows what's
/// already here at once and a refresh updates it in the background. Nothing is written to disk.
@MainActor
final class LinkHistory {
    enum Problem {
        case failed(String)
        case paused(until: Date)
    }

    /// Opening the menu more often than this reuses the last fetch. Both Macs share 500 API calls an hour.
    private static let refreshInterval: TimeInterval = 30
    /// How long to wait after a rate limit that didn't say when it resets.
    private static let defaultPause: TimeInterval = 10 * 60

    private(set) var entries: [HistoryEntry] = []
    /// False until the first fetch works, so the menu can say it's loading rather than empty.
    private(set) var hasLoaded = false
    private(set) var isFetching = false
    private var problem: Problem?

    var credentials: () -> CloudinaryCredentials? = { nil }
    var onChange: () -> Void = {}

    private var fetched: [HistoryEntry] = []
    /// This Mac's own Uploads, kept until a fetch lists them, because search takes a few seconds to catch up.
    private var unconfirmed: [HistoryEntry] = []
    private var thumbnails: [String: NSImage] = [:]
    private var thumbnailsLoading: Set<String> = []
    private var lastFetch: Date?
    /// Bumped when the Cloudinary URL changes, so a fetch for the old one is ignored.
    private var generation = 0
    private var search: HistorySearch?

    /// What the menu should say under the entries, if anything. A pause that has passed isn't shown.
    var currentProblem: Problem? {
        if case let .paused(until) = problem, until <= Date() { return nil }
        return problem
    }

    func thumbnail(for entry: HistoryEntry) -> NSImage? {
        thumbnails[entry.publicID]
    }

    /// Adds one of this Mac's own Uploads straight away.
    func add(_ entry: HistoryEntry, thumbnail: NSImage?) {
        unconfirmed = Array(([entry] + unconfirmed).prefix(HistorySearch.limit))
        if let thumbnail { thumbnails[entry.publicID] = thumbnail }
        update()
        onChange()
    }

    /// Fetches the newest Uploads unless the last fetch was recent, one is running, or Cloudinary asked us to wait.
    func refresh() {
        guard !isFetching, let credentials = credentials() else { return }
        let now = Date()
        if case let .paused(until) = problem, now < until { return }
        if let lastFetch, now.timeIntervalSince(lastFetch) < Self.refreshInterval { return }

        isFetching = true
        lastFetch = now
        let search = search(for: credentials)
        let generation = generation
        Task {
            let result: Result<[HistoryEntry], any Error>
            do {
                result = .success(try await search.recentUploads())
            } catch {
                result = .failure(error)
            }
            finish(result, startedAt: now, generation: generation)
        }
    }

    /// Starts over after the Cloudinary URL changes: the old list may belong to another cloud.
    func reset() {
        generation += 1
        search?.invalidate()
        search = nil
        entries = []
        fetched = []
        unconfirmed = []
        thumbnails = [:]
        thumbnailsLoading = []
        hasLoaded = false
        isFetching = false
        problem = nil
        lastFetch = nil
        onChange()
        refresh()
    }

    private func finish(_ result: Result<[HistoryEntry], any Error>, startedAt: Date, generation: Int) {
        guard generation == self.generation else { return }
        isFetching = false
        switch result {
        case let .success(list):
            fetched = list
            unconfirmed = HistorySearch.stillUnconfirmed(unconfirmed, fetched: list, fetchStartedAt: startedAt)
            hasLoaded = true
            problem = nil
        case let .failure(HistoryFetchError.rateLimited(until)):
            log.error("Link History paused: \(String(describing: HistoryFetchError.rateLimited(until: until)), privacy: .public)")
            problem = .paused(until: until ?? startedAt.addingTimeInterval(Self.defaultPause))
        case let .failure(error):
            log.error("Link History refresh failed: \(String(describing: error), privacy: .public)")
            problem = .failed(error.localizedDescription)
        }
        update()
        onChange()
    }

    private func update() {
        entries = HistorySearch.combine(fetched: fetched, unconfirmed: unconfirmed)
        let shown = Set(entries.map(\.publicID))
        thumbnails = thumbnails.filter { shown.contains($0.key) }
        loadThumbnails()
    }

    /// Fetches a Cloudinary-cropped thumbnail for each image without one. A failure is retried after the next fetch.
    private func loadThumbnails() {
        guard let search else { return }
        let generation = generation
        let side = HistoryRowView.thumbnailSide
        for entry in entries where entry.kind == .image
            && thumbnails[entry.publicID] == nil && !thumbnailsLoading.contains(entry.publicID) {
            thumbnailsLoading.insert(entry.publicID)
            Task {
                let image = await search.thumbnail(publicID: entry.publicID, side: Int(side * 2))
                guard generation == self.generation else { return }
                thumbnailsLoading.remove(entry.publicID)
                guard let image, entries.contains(where: { $0.publicID == entry.publicID }) else { return }
                thumbnails[entry.publicID] = NSImage(cgImage: image, size: NSSize(width: side, height: side))
                onChange()
            }
        }
    }

    /// Swaps in a new HistorySearch only when the Cloudinary URL has changed.
    private func search(for credentials: CloudinaryCredentials) -> HistorySearch {
        if let search, search.credentials == credentials { return search }
        search?.invalidate()
        let fresh = HistorySearch(credentials: credentials)
        search = fresh
        return fresh
    }
}
