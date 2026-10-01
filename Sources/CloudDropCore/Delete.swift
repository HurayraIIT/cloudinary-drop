import Foundation

public enum DeleteError: LocalizedError, CustomStringConvertible, Equatable, Sendable {
    /// A 403. The menu explains it in plain words; Cloudinary's own message is kept for the log.
    case notAllowedToDelete(cloudinaryMessage: String?)
    case cloudinary(String)
    case unexpectedResponse(Int)

    public var errorDescription: String? {
        switch self {
        case .notAllowedToDelete: "This API key isn't allowed to delete. Use a key with delete access."
        case let .cloudinary(message): message
        case let .unexpectedResponse(status): "Cloudinary answered with HTTP \(status)"
        }
    }

    /// What the log shows.
    public var description: String {
        switch self {
        case let .notAllowedToDelete(message?): "\(errorDescription ?? "") Cloudinary said: \(message) (HTTP 403)"
        default: errorDescription ?? ""
        }
    }
}

public enum DeleteOutcome: Equatable, Sendable {
    case deleted
    /// Cloudinary had no such file, e.g. it was Deleted from the other Mac. It's gone either way.
    case alreadyGone
}

/// Deletes with the Upload API's signed `destroy`, which doesn't spend the Admin API's hourly limit that the
/// Link History's search shares (ADR 0007).
extension Uploader {
    public func delete(publicID: String, kind: MediaKind) async throws -> DeleteOutcome {
        let request = Self.deleteRequest(credentials: credentials, publicID: publicID, kind: kind, timestamp: Date())
        let (data, response) = try await session.data(for: request)
        return try Self.deleteOutcome(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }

    /// Signs a Delete of a public_id that can't exist. A key that may delete gets `"not found"`; one that may not gets 403.
    public static func probeDeletePermission(_ credentials: CloudinaryCredentials) async throws {
        var request = deleteRequest(
            credentials: credentials, publicID: "clouddrop-delete-probe-\(UUID().uuidString)", kind: .image, timestamp: Date())
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        _ = try deleteOutcome(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }

    /// `invalidate` purges Cloudinary's CDN cache, so the Share Link stops working within minutes.
    static func deleteRequest(credentials: CloudinaryCredentials, publicID: String, kind: MediaKind, timestamp: Date) -> URLRequest {
        var params = [
            "invalidate": "true",
            "public_id": publicID,
            "timestamp": String(Int(timestamp.timeIntervalSince1970)),
        ]
        params["signature"] = uploadSignature(params, secret: credentials.apiSecret)
        params["api_key"] = credentials.apiKey

        var request = URLRequest(url: URL(string: "https://api.cloudinary.com/v1_1/\(credentials.cloudName)/\(kind.rawValue)/destroy")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncoded(params).utf8)
        return request
    }

    static func deleteOutcome(status: Int, data: Data) throws -> DeleteOutcome {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if status == 200 {
            switch json?["result"] as? String {
            case "ok": return .deleted
            case "not found": return .alreadyGone
            case let result?: throw DeleteError.cloudinary("Cloudinary answered \"\(result)\"")
            case nil: throw DeleteError.unexpectedResponse(status)
            }
        }
        let message = errorMessage(in: data)
        if status == 403 { throw DeleteError.notAllowedToDelete(cloudinaryMessage: message) }
        if status == 401 { throw DeleteError.cloudinary("Cloudinary rejected the API key or secret") }
        if let message { throw DeleteError.cloudinary("\(message) (HTTP \(status))") }
        throw DeleteError.unexpectedResponse(status)
    }

    /// Older public_ids carry the original filename, so values are percent-encoded.
    private static func formEncoded(_ params: [String: String]) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return params.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
    }
}
