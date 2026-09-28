import CryptoKit
import Foundation

public enum UploadError: LocalizedError, Sendable {
    case cloudinary(String)
    case unexpectedResponse(Int)

    public var errorDescription: String? {
        switch self {
        case let .cloudinary(message): message
        case let .unexpectedResponse(status): "Cloudinary answered with HTTP \(status)"
        }
    }
}

/// Signs a set of upload parameters the way Cloudinary expects: sorted `key=value` pairs
/// joined with `&`, followed by the API secret, hashed with SHA-1.
public func uploadSignature(_ params: [String: String], secret: String) -> String {
    let payload = params
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: "&") + secret
    return Insecure.SHA1.hash(data: Data(payload.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
}

/// Sends Media Files straight to Cloudinary's signed upload API (ADR 0003).
public struct Uploader: Sendable {
    let credentials: CloudinaryCredentials
    let session: URLSession

    public init(credentials: CloudinaryCredentials) {
        self.credentials = credentials
        let configuration = URLSessionConfiguration.ephemeral
        // No overall deadline: a 100 MB video on slow Wi-Fi may take minutes.
        // Only give up when the connection stalls.
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        session = URLSession(configuration: configuration)
    }

    /// Uploads one Media File and returns its `secure_url`.
    public func upload(
        fileURL: URL,
        kind: MediaKind,
        publicID: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        var params = [
            "asset_folder": PublicID.folder,
            "public_id": publicID,
            "timestamp": String(Int(Date().timeIntervalSince1970)),
        ]
        params["signature"] = uploadSignature(params, secret: credentials.apiSecret)
        params["api_key"] = credentials.apiKey

        let boundary = "CloudDrop-\(UUID().uuidString)"
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clouddrop-\(UUID().uuidString).multipart")
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        try writeMultipartBody(to: bodyURL, boundary: boundary, params: params, fileURL: fileURL)

        var request = URLRequest(url: URL(string: "https://api.cloudinary.com/v1_1/\(credentials.cloudName)/\(kind.rawValue)/upload")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.upload(
            for: request, fromFile: bodyURL, delegate: ProgressDelegate(onProgress: progress))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        if status == 200, let secure = json?["secure_url"] as? String, let url = URL(string: secure) {
            return url
        }
        if status == 403 { throw UploadError.cloudinary(Self.cannotUploadMessage) }
        if let message = Self.errorMessage(in: data) {
            throw UploadError.cloudinary("\(message) (HTTP \(status))")
        }
        throw UploadError.unexpectedResponse(status)
    }

    static let cannotUploadMessage = "This API key isn't allowed to upload (it lacks Cloudinary's \"create\" permission). Use a key with upload access."

    /// Checks that a Cloudinary URL is accepted and that its key may upload. Creates nothing.
    public static func verify(_ credentials: CloudinaryCredentials) async throws {
        try await ping(credentials)
        try await probeUploadPermission(credentials)
    }

    private static func ping(_ credentials: CloudinaryCredentials) async throws {
        var request = URLRequest(url: URL(string: "https://api.cloudinary.com/v1_1/\(credentials.cloudName)/ping")!)
        let auth = Data("\(credentials.apiKey):\(credentials.apiSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let (_, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: return
        case 401: throw UploadError.cloudinary("Cloudinary rejected the API key or secret")
        case 404: throw UploadError.cloudinary("Cloudinary doesn't know the cloud name \(credentials.cloudName)")
        case let status: throw UploadError.unexpectedResponse(status)
        }
    }

    /// Sends a signed upload request without a file. A key that may upload gets
    /// "Missing required parameter - file". A key without upload permission gets 403.
    private static func probeUploadPermission(_ credentials: CloudinaryCredentials) async throws {
        var params = ["timestamp": String(Int(Date().timeIntervalSince1970))]
        params["signature"] = uploadSignature(params, secret: credentials.apiSecret)
        params["api_key"] = credentials.apiKey

        var request = URLRequest(url: URL(string: "https://api.cloudinary.com/v1_1/\(credentials.cloudName)/image/upload")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(params.map { "\($0.key)=\($0.value)" }.joined(separator: "&").utf8)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let message = errorMessage(in: data) ?? ""
        switch status {
        case 400 where message.localizedCaseInsensitiveContains("file"): return
        case 403: throw UploadError.cloudinary(cannotUploadMessage)
        case 401: throw UploadError.cloudinary("Cloudinary rejected the API key or secret")
        default: throw UploadError.cloudinary(message.isEmpty ? "Cloudinary answered with HTTP \(status)" : message)
        }
    }

    private static func errorMessage(in data: Data) -> String? {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (json?["error"] as? [String: Any])?["message"] as? String
    }

    /// Streams the file into a multipart body on disk so large videos never sit in memory.
    private func writeMultipartBody(to bodyURL: URL, boundary: String, params: [String: String], fileURL: URL) throws {
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: bodyURL)
        defer { try? output.close() }

        for (name, value) in params.sorted(by: { $0.key < $1.key }) {
            try output.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        let filename = "upload.\(fileURL.pathExtension.isEmpty ? "bin" : fileURL.pathExtension.lowercased())"
        try output.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))

        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        // Without the pool, every 1 MB chunk stays alive until the upload finishes.
        var copying = true
        while copying {
            try autoreleasepool {
                guard let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty else {
                    copying = false
                    return
                }
                try output.write(contentsOf: chunk)
            }
        }
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    }
}

private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
