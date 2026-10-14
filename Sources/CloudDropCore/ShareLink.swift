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

    /// The size next to each Link History entry and in the Usage line, in the same binary units as the Size Limit
    /// messages: `850 KB` under 1 MB, `4.2 MB` under 10 MB, `87 MB` under 1000 MB, then `1.3 GB`.
    public static func fileSize(_ bytes: Int64) -> String {
        let kilobytes = (Double(bytes) / 1024).rounded()
        if kilobytes < 1024 { return "\(bytes > 0 ? max(1, Int(kilobytes)) : 0) KB" }
        let megabytes = Double(bytes) / 1_048_576
        let tenths = (megabytes * 10).rounded() / 10
        if tenths < 10 { return String(format: "%.1f MB", tenths) }
        if megabytes.rounded() < 1000 { return "\(Int(megabytes.rounded())) MB" }
        return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }
}
