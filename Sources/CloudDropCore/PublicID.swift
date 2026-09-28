import Foundation

/// Builds the Cloudinary `public_id` for an Upload, which becomes the readable part of the Share Link:
/// `clouddrop/260928_141503_k3f9_screenshot`.
public enum PublicID {
    public static let folder = "clouddrop"
    public static let maxSlugLength = 40

    public static func make(
        originalFilename: String,
        date: Date = Date(),
        randomSuffix: String = randomSuffix(),
        timeZone: TimeZone = .current
    ) -> String {
        var name = "\(timestamp(date, timeZone: timeZone))_\(randomSuffix)"
        let slug = slug(fromFilename: originalFilename)
        if !slug.isEmpty { name += "_\(slug)" }
        return "\(folder)/\(name)"
    }

    /// Lowercases the name without its extension, turns anything outside `a-z 0-9 _ -` into `-`,
    /// collapses runs of `-` and caps the length.
    public static func slug(fromFilename filename: String) -> String {
        let base = (filename as NSString).deletingPathExtension.lowercased()
        var slug = ""
        for scalar in base.unicodeScalars {
            let allowed = ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "-"
            let next: Character = allowed ? Character(scalar) : "-"
            if next == "-", slug.last == "-" { continue }
            slug.append(next)
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(slug.prefix(maxSlugLength)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    public static func randomSuffix(length: Int = 4) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }

    static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyMMdd_HHmmss"
        return formatter.string(from: date)
    }
}
