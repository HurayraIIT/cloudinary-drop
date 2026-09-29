import Foundation

public enum ShareLink {
    /// The Share Link for an Upload, built from what Cloudinary stored rather than its `secure_url` (ADR 0005).
    /// It has no version, because a name is never reused, and images drop `/image/upload`, which Cloudinary
    /// assumes when it's missing. HEIC/HEIF is delivered as JPEG so every browser can show it.
    public static func make(cloudName: String, kind: MediaKind, file: UploadedFile) -> URL {
        let format = file.format.lowercased()
        let path = switch kind {
        case .image: "\(file.publicID).\(["heic", "heif"].contains(format) ? "jpg" : format)"
        case .video: "video/upload/\(file.publicID).\(format)"
        }
        return URL(string: "https://res.cloudinary.com/\(cloudName)/\(path)")!
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
