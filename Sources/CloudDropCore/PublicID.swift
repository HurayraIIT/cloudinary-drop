import Foundation

/// Builds the Cloudinary `public_id` for an Upload: a random name in a one-letter folder, `d/k3f9x2ab`,
/// so the Share Link stays short and never reveals the original filename (ADR 0005).
public enum PublicID {
    /// The folder in the Share Link's path.
    public static let folder = "d"
    /// The folder shown in the Cloudinary console. With dynamic folders it's independent of `folder`.
    public static let assetFolder = "clouddrop"
    public static let nameLength = 8

    public static func make(name: String = randomName()) -> String {
        "\(folder)/\(name)"
    }

    public static func randomName(length: Int = nameLength) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }
}
