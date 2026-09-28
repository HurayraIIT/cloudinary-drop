import CloudDropCore
import Foundation
import Security

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

    static func load() -> CloudinaryCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
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
