import CoreGraphics
import Foundation

/// One Upload in the Link History, from this Mac or the other one.
public struct HistoryEntry: Equatable, Sendable {
    public let publicID: String
    public let kind: MediaKind
    /// The original filename, as sent in `display_name`.
    public let filename: String
    /// By Cloudinary's clock, so entries from both Macs sort together.
    public let uploadedAt: Date
    public let shareLink: URL
    /// Cloudinary's `bytes`, the size of the Media File as dropped. Nil when Cloudinary didn't say.
    public let byteCount: Int64?

    public init(publicID: String, kind: MediaKind, filename: String, uploadedAt: Date, shareLink: URL, byteCount: Int64? = nil) {
        self.publicID = publicID
        self.kind = kind
        self.filename = filename
        self.uploadedAt = uploadedAt
        self.shareLink = shareLink
        self.byteCount = byteCount
    }
}

public enum HistoryFetchError: LocalizedError, CustomStringConvertible, Equatable, Sendable {
    /// The key may upload but not search (Cloudinary answered 403).
    case notAllowedToList(cloudinaryMessage: String?)
    /// The account's hourly Admin API limit, shared by both Macs. Nil when Cloudinary didn't say when it resets.
    case rateLimited(until: Date?)
    case cloudinary(String)
    case unexpectedResponse(Int)

    public var errorDescription: String? {
        switch self {
        case .notAllowedToList: "This API key isn't allowed to list uploads"
        case .rateLimited: "Cloudinary's hourly API limit was reached"
        case let .cloudinary(message): message
        case let .unexpectedResponse(status): "Cloudinary answered with HTTP \(status)"
        }
    }

    /// What the log shows.
    public var description: String {
        switch self {
        case let .notAllowedToList(message?): "\(errorDescription ?? "") Cloudinary said: \(message) (HTTP 403)"
        case let .rateLimited(until?): "\(errorDescription ?? "") until \(until)"
        default: errorDescription ?? ""
        }
    }
}

/// Reads the newest Uploads in the `clouddrop` asset folder with Cloudinary's Search API, so the Link History
/// shows what either Mac uploaded (ADR 0006). Keep one per Cloudinary URL and `invalidate()` it when replaced.
public struct HistorySearch: Sendable {
    public static let limit = 10
    /// Search can take a few seconds to show a fresh Upload. A fetch that started this long after one of our own
    /// Uploads and still doesn't list it means the file is gone, e.g. deleted in the console.
    public static let indexingGrace: TimeInterval = 120

    public let credentials: CloudinaryCredentials
    let session: URLSession

    public init(credentials: CloudinaryCredentials) {
        self.credentials = credentials
        // Ephemeral, so thumbnails never land in a disk cache: the Link History stays in memory.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    public func invalidate() {
        session.finishTasksAndInvalidate()
    }

    /// The newest Uploads, newest first.
    public func recentUploads(limit: Int = HistorySearch.limit) async throws -> [HistoryEntry] {
        let (data, response) = try await session.data(for: Self.request(credentials: credentials, limit: limit))
        let http = response as? HTTPURLResponse
        return try Self.entries(
            status: http?.statusCode ?? 0,
            data: data,
            rateLimitReset: http?.value(forHTTPHeaderField: "X-FeatureRateLimit-Reset"),
            cloudName: credentials.cloudName)
    }

    /// A small square preview of an image Upload, cropped by Cloudinary. Nil if it can't be fetched or decoded.
    public func thumbnail(publicID: String, side: Int) async -> CGImage? {
        let url = Thumbnail.url(cloudName: credentials.cloudName, publicID: publicID, side: side)
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return Thumbnail.decode(data)
    }

    static func request(credentials: CloudinaryCredentials, limit: Int) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.cloudinary.com/v1_1/\(credentials.cloudName)/resources/search")!)
        request.httpMethod = "POST"
        let auth = Data("\(credentials.apiKey):\(credentials.apiSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "expression": "asset_folder=\(PublicID.assetFolder)",
            "sort_by": [["created_at": "desc"]],
            "max_results": limit,
            "fields": ["public_id", "format", "resource_type", "created_at", "display_name", "bytes"],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
        return request
    }

    /// Reads Cloudinary's answer to a search. Anything that isn't an image or video is skipped.
    static func entries(status: Int, data: Data, rateLimitReset: String?, cloudName: String) throws -> [HistoryEntry] {
        switch status {
        case 200:
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            guard let resources = json?["resources"] as? [[String: Any]] else { throw HistoryFetchError.unexpectedResponse(status) }
            return resources.compactMap { entry(from: $0, cloudName: cloudName) }
        case 420, 429:
            throw HistoryFetchError.rateLimited(until: rateLimitReset.flatMap(httpDate))
        case 401:
            throw HistoryFetchError.cloudinary("Cloudinary rejected the API key or secret")
        case 403:
            throw HistoryFetchError.notAllowedToList(cloudinaryMessage: Uploader.errorMessage(in: data))
        default:
            if let message = Uploader.errorMessage(in: data) { throw HistoryFetchError.cloudinary("\(message) (HTTP \(status))") }
            throw HistoryFetchError.unexpectedResponse(status)
        }
    }

    private static func entry(from resource: [String: Any], cloudName: String) -> HistoryEntry? {
        guard let publicID = resource["public_id"] as? String,
              let format = resource["format"] as? String,
              let kind = (resource["resource_type"] as? String).flatMap(MediaKind.init(rawValue:)),
              let createdAt = (resource["created_at"] as? String).flatMap({ try? Date($0, strategy: .iso8601) })
        else { return nil }
        let displayName = (resource["display_name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return HistoryEntry(
            publicID: publicID,
            kind: kind,
            filename: displayName.isEmpty ? String(publicID.split(separator: "/").last ?? "") : displayName,
            uploadedAt: createdAt,
            shareLink: ShareLink.make(cloudName: cloudName, kind: kind, file: UploadedFile(publicID: publicID, format: format)),
            byteCount: (resource["bytes"] as? NSNumber)?.int64Value)
    }

    /// Parses `Wed, 30 Sep 2026 07:00:00 GMT`.
    static func httpDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: text)
    }

    /// The Link History to show: fetched entries plus this Mac's own Uploads that search may not list yet.
    public static func combine(fetched: [HistoryEntry], unconfirmed: [HistoryEntry], limit: Int = limit) -> [HistoryEntry] {
        let fetchedIDs = Set(fetched.map(\.publicID))
        let merged = fetched + unconfirmed.filter { !fetchedIDs.contains($0.publicID) }
        return Array(merged.sorted { $0.uploadedAt > $1.uploadedAt }.prefix(limit))
    }

    /// Which of this Mac's own Uploads still need to be kept after a successful fetch: the ones it doesn't list
    /// yet, unless the fetch started long enough after the Upload that search should have caught up.
    public static func stillUnconfirmed(_ unconfirmed: [HistoryEntry], fetched: [HistoryEntry], fetchStartedAt: Date) -> [HistoryEntry] {
        let fetchedIDs = Set(fetched.map(\.publicID))
        return unconfirmed.filter {
            !fetchedIDs.contains($0.publicID) && fetchStartedAt.timeIntervalSince($0.uploadedAt) < indexingGrace
        }
    }
}

/// The short time next to each Link History entry.
public enum HistoryTime {
    /// `02:34 PM` today, `Yesterday`, `Mon` within the last week, then `12 Sep`, with the year once it's a past year.
    public static func label(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let format: String
        if calendar.isDate(date, inSameDayAs: now) {
            format = clockFormat
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        } else if let weekAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)), date >= weekAgo, date < now {
            format = "EEE"
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            format = "d MMM"
        } else {
            format = "d MMM yyyy"
        }
        return string(date, format: format, calendar: calendar)
    }

    /// The full date and time, for the tooltip.
    public static func full(_ date: Date, calendar: Calendar = .current) -> String {
        string(date, format: "d MMM yyyy 'at' \(clockFormat)", calendar: calendar)
    }

    /// The 12-hour time of day, `02:34 PM`, used everywhere the menu shows one.
    public static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        string(date, format: clockFormat, calendar: calendar)
    }

    private static let clockFormat = "hh:mm a"

    private static func string(_ date: Date, format: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
