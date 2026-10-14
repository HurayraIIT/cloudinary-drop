import Foundation

/// The whole account's Usage, as the menu's one line shows it. The stored bytes and credits come from the Usage API,
/// which Cloudinary updates once a day; the counts come from two searches. Nil until each has been read.
public struct Usage: Equatable, Sendable {
    public var storedBytes: Int64?
    /// Cloudinary's `used_percent` of the monthly credits. The Free plan has no storage limit of its own,
    /// so this is the only measure of what's left.
    public var creditsUsedPercent: Double?
    public var images: Int?
    public var videos: Int?

    public init(storedBytes: Int64? = nil, creditsUsedPercent: Double? = nil, images: Int? = nil, videos: Int? = nil) {
        self.storedBytes = storedBytes
        self.creditsUsedPercent = creditsUsedPercent
        self.images = images
        self.videos = videos
    }

    /// `1,210 images · 26 videos · 636 MB · 12% of credits`. Nil until everything is known, so the menu hides it.
    public var line: String? {
        guard let storedBytes, let creditsUsedPercent, let images, let videos else { return nil }
        return [
            Self.count(images, "image"),
            Self.count(videos, "video"),
            MenuText.fileSize(storedBytes),
            "\(Self.percent(creditsUsedPercent)) of credits",
        ].joined(separator: " · ")
    }

    static func count(_ number: Int, _ noun: String) -> String {
        "\(number.formatted(.number.locale(Locale(identifier: "en_US")))) \(noun)\(number == 1 ? "" : "s")"
    }

    static func percent(_ value: Double) -> String {
        value > 0 && value < 0.5 ? "<1%" : "\(Int(value.rounded()))%"
    }
}

/// When one of the Usage line's calls is due. Each call costs some of the hourly Admin API limit, so they're spread out.
public struct UsageSchedule: Sendable {
    /// The least time between two tries, so a failure isn't retried on every menu open.
    public static let retryInterval: TimeInterval = 30
    /// Search takes a few seconds to count a fresh Upload or forget a Deleted one.
    public static let indexingDelay: TimeInterval = 15

    public let interval: TimeInterval
    public var isFetching = false
    public var lastTry: Date?
    /// When the last call that gave an answer worth keeping started.
    public var lastAnswer: Date?

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Due once `interval` has passed since the last answer, or when that answer may predate a change this Mac made.
    public func isDue(at now: Date, changedAt: Date? = nil) -> Bool {
        if isFetching { return false }
        if let lastTry, now.timeIntervalSince(lastTry) < Self.retryInterval { return false }
        guard let lastAnswer else { return true }
        if let changedAt, lastAnswer < changedAt.addingTimeInterval(Self.indexingDelay) { return true }
        return now.timeIntervalSince(lastAnswer) >= interval
    }
}

/// Reads the account's Usage with the Admin API. Every call counts toward the 500 an hour that both Macs share
/// with the Link History. Keep one per Cloudinary URL and `invalidate()` it when replaced.
public struct UsageReader: Sendable {
    public let credentials: CloudinaryCredentials
    let session: URLSession

    public init(credentials: CloudinaryCredentials) {
        self.credentials = credentials
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    public func invalidate() {
        session.finishTasksAndInvalidate()
    }

    /// The stored bytes and the share of the monthly credits used, as of Cloudinary's last daily update.
    public func storage() async throws -> Usage {
        let (data, response) = try await session.data(for: Self.storageRequest(credentials: credentials))
        let http = response as? HTTPURLResponse
        return try Self.storage(
            status: http?.statusCode ?? 0, data: data,
            rateLimitReset: http?.value(forHTTPHeaderField: "X-FeatureRateLimit-Reset"))
    }

    /// How many images or videos the whole account holds.
    public func count(of kind: MediaKind) async throws -> Int {
        let (data, response) = try await session.data(for: Self.countRequest(credentials: credentials, kind: kind))
        let http = response as? HTTPURLResponse
        return try Self.count(
            status: http?.statusCode ?? 0, data: data,
            rateLimitReset: http?.value(forHTTPHeaderField: "X-FeatureRateLimit-Reset"))
    }

    static func storageRequest(credentials: CloudinaryCredentials) -> URLRequest {
        HistorySearch.adminRequest(credentials: credentials, path: "usage")
    }

    /// Asks for no resources, only `total_count`.
    static func countRequest(credentials: CloudinaryCredentials, kind: MediaKind) -> URLRequest {
        HistorySearch.searchRequest(credentials: credentials, body: ["expression": "resource_type:\(kind.rawValue)", "max_results": 0])
    }

    static func storage(status: Int, data: Data, rateLimitReset: String?) throws -> Usage {
        guard status == 200 else { throw HistorySearch.failure(status: status, data: data, rateLimitReset: rateLimitReset) }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let bytes = ((json?["storage"] as? [String: Any])?["usage"] as? NSNumber)?.int64Value,
              let percent = ((json?["credits"] as? [String: Any])?["used_percent"] as? NSNumber)?.doubleValue
        else { throw HistoryFetchError.unexpectedResponse(status) }
        return Usage(storedBytes: bytes, creditsUsedPercent: percent)
    }

    static func count(status: Int, data: Data, rateLimitReset: String?) throws -> Int {
        guard status == 200 else { throw HistorySearch.failure(status: status, data: data, rateLimitReset: rateLimitReset) }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let total = (json?["total_count"] as? NSNumber)?.intValue else { throw HistoryFetchError.unexpectedResponse(status) }
        return total
    }
}
