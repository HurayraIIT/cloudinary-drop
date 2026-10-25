import AppKit
import CloudDropCore

/// The Link History: the newest Uploads in the account, from either Mac (ADR 0006). The popover shows what's
/// already here at once and a refresh updates it in the background. Nothing is written to disk.
@MainActor
final class LinkHistory {
    typealias Problem = RefreshStatus.Problem

    /// Opening the popover more often than this reuses the last fetch. Both Macs share 500 API calls an hour.
    private static let refreshInterval: TimeInterval = 30
    /// How long to wait after a rate limit that didn't say when it resets.
    private static let defaultPause: TimeInterval = 10 * 60

    private(set) var entries: [HistoryEntry] = []
    /// False until the first fetch works, so the menu can say it's loading rather than empty.
    private(set) var hasLoaded = false
    private(set) var isFetching = false
    private var status = RefreshStatus()

    var credentials: () -> CloudinaryCredentials? = { nil }
    var onChange: () -> Void = {}
    var onThumbnail: (String) -> Void = { _ in }

    private var fetched: [HistoryEntry] = []
    /// This Mac's own Uploads, kept until a fetch lists them, because search takes a few seconds to catch up.
    private var unconfirmed: [HistoryEntry] = []
    /// Deleted public_ids and when, hidden until a fetch stops listing them, because search takes a few seconds to catch up.
    private var deleted: [String: Date] = [:]
    private var thumbnails: [String: NSImage] = [:]
    private var thumbnailTasks: [String: Task<Void, Never>] = [:]
    private var thumbnailFailures: Set<String> = []
    private var visibleIDs: [String] = []
    private var lastFetch: Date?
    /// Bumped when the Cloudinary URL changes, so a fetch for the old one is ignored.
    private var generation = 0
    private var search: HistorySearch?

    /// What the popover should say under the entries, if anything. A pause that has passed isn't shown.
    var currentProblem: Problem? { status.problem() }

    /// True while a rate limit is in force. The Usage line's calls count toward the same limit.
    var isPaused: Bool { status.isPaused() }

    /// Pauses refreshes after another caller on the same key hit the rate limit. A fetch still running when it
    /// does doesn't end the pause.
    func pause(until: Date?) {
        status.pause(until: until ?? Date().addingTimeInterval(Self.defaultPause))
        onChange()
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

    /// Hides a Deleted Upload straight away. The list is one short until the next refresh.
    func remove(_ entry: HistoryEntry) {
        deleted[entry.publicID] = Date()
        unconfirmed.removeAll { $0.publicID == entry.publicID }
        update()
        onChange()
    }

    /// Fetches the newest Uploads unless the last fetch was recent, one is running, or Cloudinary asked us to wait.
    func refresh() {
        guard !isFetching, let credentials = credentials() else { return }
        let now = Date()
        if status.isPaused(at: now) { return }
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
        deleted = [:]
        thumbnails = [:]
        thumbnailTasks.values.forEach { $0.cancel() }
        thumbnailTasks = [:]
        thumbnailFailures = []
        visibleIDs = []
        hasLoaded = false
        isFetching = false
        status = RefreshStatus()
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
            thumbnailFailures = []
            unconfirmed = HistorySearch.stillUnconfirmed(unconfirmed, fetched: list, fetchStartedAt: startedAt)
            deleted = HistorySearch.stillDeleted(deleted, fetched: list, fetchStartedAt: startedAt)
            hasLoaded = true
            status.fetchSucceeded()
        case let .failure(HistoryFetchError.rateLimited(until)):
            log.error("Link History paused: \(String(describing: HistoryFetchError.rateLimited(until: until)), privacy: .public)")
            status.pause(until: until ?? startedAt.addingTimeInterval(Self.defaultPause))
        case let .failure(error):
            log.error("Link History refresh failed: \(String(describing: error), privacy: .public)")
            status.fetchFailed(error.localizedDescription)
        }
        update()
        onChange()
    }

    private func update() {
        entries = HistorySearch.combine(fetched: fetched, unconfirmed: unconfirmed, deleted: Set(deleted.keys))
        let shown = Set(entries.map(\.publicID))
        thumbnails = thumbnails.filter { shown.contains($0.key) }
        thumbnailFailures.formIntersection(shown)
        loadThumbnails()
    }

    /// The viewport supplies visible entries first, then a small lookahead. A closed popover requests none.
    func showThumbnails(for publicIDs: [String]) {
        visibleIDs = publicIDs
        loadThumbnails()
    }

    /// At most two requests run at once; failures wait for the next successful history fetch before retrying.
    private func loadThumbnails() {
        guard let search else { return }
        let wanted = visibleIDs.compactMap { id in entries.first { $0.publicID == id && $0.kind == .image } }
        for entry in wanted where thumbnailTasks.count < 2 && thumbnails[entry.publicID] == nil
            && thumbnailTasks[entry.publicID] == nil && !thumbnailFailures.contains(entry.publicID) {
            let id = entry.publicID
            let generation = generation
            thumbnailTasks[id] = Task { [weak self] in
                let image = await search.thumbnail(publicID: id, side: HistoryRowView.thumbnailPixels)
                guard let self, generation == self.generation else { return }
                thumbnailTasks.removeValue(forKey: id)
                if entries.contains(where: { $0.publicID == id }) {
                    if let image {
                        if thumbnails[id] == nil {
                            thumbnails[id] = NSImage(cgImage: image, size: NSSize(width: HistoryRowView.thumbnailSide,
                                                                              height: HistoryRowView.thumbnailSide))
                        }
                        onThumbnail(id)
                    } else {
                        thumbnailFailures.insert(id)
                    }
                }
                loadThumbnails()
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
