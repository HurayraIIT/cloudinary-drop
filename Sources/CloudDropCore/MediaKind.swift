import Foundation
import UniformTypeIdentifiers

/// What a Media File is, as far as Cloudinary is concerned.
public enum MediaKind: String, Sendable {
    case image
    case video

    public init?(type: UTType) {
        if type.conforms(to: .image) {
            self = .image
        } else if type.conforms(to: .movie) {
            self = .video
        } else {
            return nil
        }
    }

    public init?(fileExtension: String) {
        guard let type = UTType(filenameExtension: fileExtension) else { return nil }
        self.init(type: type)
    }

    /// The account's Size Limit for this kind (Cloudinary Free plan, see ADR 0003).
    public var sizeLimit: Int64 {
        switch self {
        case .image: 10_485_760
        case .video: 104_857_600
        }
    }
}

/// Why a file in a Drop was refused before uploading.
public enum Refusal: Error, Equatable, Sendable {
    case notMedia(filename: String)
    case unreadable(filename: String)
    case tooLarge(filename: String, kind: MediaKind, byteCount: Int64)

    public var message: String {
        switch self {
        case let .notMedia(filename):
            "\(filename) isn't an image or video"
        case let .unreadable(filename):
            "\(filename) couldn't be read"
        case let .tooLarge(filename, kind, byteCount):
            "\(filename) is \(megabytes(byteCount)), \(kind.rawValue) limit is \(megabytes(kind.sizeLimit))"
        }
    }
}

/// Decides whether a dropped file is a Media File within its Size Limit.
/// An unknown size is refused rather than let past the Size Limit.
public func checkMediaFile(filename: String, type: UTType?, byteCount: Int64?) -> Result<MediaKind, Refusal> {
    guard let type, let kind = MediaKind(type: type) else {
        return .failure(.notMedia(filename: filename))
    }
    guard let byteCount else {
        return .failure(.unreadable(filename: filename))
    }
    guard byteCount <= kind.sizeLimit else {
        return .failure(.tooLarge(filename: filename, kind: kind, byteCount: byteCount))
    }
    return .success(kind)
}

func megabytes(_ bytes: Int64) -> String {
    let value = Double(bytes) / 1_048_576
    let rounded = (value * 10).rounded() / 10
    return rounded == rounded.rounded()
        ? "\(Int(rounded)) MB"
        : String(format: "%.1f MB", rounded)
}
