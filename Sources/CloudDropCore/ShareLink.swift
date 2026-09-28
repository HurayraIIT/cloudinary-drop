import Foundation

public enum ShareLink {
    /// The Share Link for an uploaded file's `secure_url`: the original, except HEIC/HEIF,
    /// which is delivered as JPEG so every browser can show it.
    public static func make(secureURL: URL) -> URL {
        switch secureURL.pathExtension.lowercased() {
        case "heic", "heif":
            secureURL.deletingPathExtension().appendingPathExtension("jpg")
        default:
            secureURL
        }
    }
}

public enum MenuText {
    /// Shortens long names in the middle so both the start and the extension stay visible.
    public static func truncateMiddle(_ text: String, maxLength: Int = 30) -> String {
        guard text.count > maxLength, maxLength > 1 else { return text }
        let keep = maxLength - 1
        let head = (keep + 1) / 2
        return String(text.prefix(head)) + "…" + String(text.suffix(keep - head))
    }
}
