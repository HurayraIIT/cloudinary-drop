import Foundation

/// The parts of a Cloudinary URL (`cloudinary://key:secret@cloud`).
public struct CloudinaryCredentials: Equatable, Sendable {
    public let apiKey: String
    public let apiSecret: String
    public let cloudName: String

    public init(apiKey: String, apiSecret: String, cloudName: String) {
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        self.cloudName = cloudName
    }

    /// Parses a pasted Cloudinary URL. Tolerates a whole `.zshrc` line
    /// (`export CLOUDINARY_URL="…"`), surrounding quotes and whitespace.
    public init?(parsing raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("export ") {
            text = String(text.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
        }
        if text.hasPrefix("CLOUDINARY_URL=") {
            text = String(text.dropFirst("CLOUDINARY_URL=".count))
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))

        let scheme = "cloudinary://"
        guard text.hasPrefix(scheme) else { return nil }
        let rest = text.dropFirst(scheme.count)
        guard let at = rest.lastIndex(of: "@") else { return nil }

        let userInfo = rest[..<at]
        var cloud = rest[rest.index(after: at)...]
        if let query = cloud.firstIndex(where: { $0 == "?" || $0 == "/" }) {
            cloud = cloud[..<query]
        }
        guard let colon = userInfo.firstIndex(of: ":") else { return nil }
        let key = String(userInfo[..<colon])
        let secret = String(userInfo[userInfo.index(after: colon)...])

        let forbidden = CharacterSet.whitespacesAndNewlines
        guard !key.isEmpty, !secret.isEmpty, !cloud.isEmpty,
              [key, secret, String(cloud)].allSatisfy({ $0.rangeOfCharacter(from: forbidden) == nil })
        else { return nil }

        self.init(apiKey: key, apiSecret: secret, cloudName: String(cloud))
    }

    public var urlString: String { "cloudinary://\(apiKey):\(apiSecret)@\(cloudName)" }
}
