import CloudDropCore
import Foundation
import Security

/// Why there's no Cloudinary URL to upload with.
enum CredentialsError: LocalizedError, CustomStringConvertible {
    case notSet
    case unreadable(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notSet: "Set Cloudinary URL first"
        case .unreadable: "Couldn't read the Cloudinary URL from the Keychain"
        }
    }

    /// What the log shows.
    var description: String {
        switch self {
        case .notSet: errorDescription ?? ""
        case let .unreadable(status): "\(errorDescription ?? ""): \(SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)")"
        }
    }
}

/// Keeps the Cloudinary URL in the login Keychain (ADR 0002).
enum KeychainStore {
    private static let service = "com.hurayraiit.clouddrop"
    private static let account = "CLOUDINARY_URL"

    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Couldn't save to the Keychain: \(detail)"
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Nil when no Cloudinary URL is saved. Any other failure, such as Deny on the prompt after a rebuild,
    /// throws, so it isn't mistaken for a missing URL.
    static func load() throws(CredentialsError) -> CloudinaryCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8)
        else { throw .unreadable(status) }
        return CloudinaryCredentials(parsing: text)
    }

    static func save(_ credentials: CloudinaryCredentials) throws {
        SecItemDelete(baseQuery as CFDictionary)
        var item = baseQuery
        item[kSecValueData as String] = Data(credentials.urlString.utf8)
        item[kSecAttrLabel as String] = "CloudDrop Cloudinary URL"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
}
