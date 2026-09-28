import CoreGraphics
import Foundation
import ImageIO

/// The small square preview of an image in the Link History.
public enum Thumbnail {
    /// A centre-cropped square of an image file, `side` pixels across. ImageIO decodes straight to the
    /// small size, so a 10 MB photo is never held in memory. Nil when the file isn't a decodable image.
    public static func make(imageAt url: URL, side: Int) -> CGImage? {
        guard side > 0,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }

        // Scale so the shorter edge is still `side`, then crop the middle.
        let longest = (Double(side) * Double(max(width, height)) / Double(min(width, height))).rounded(.up)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(longest),
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let crop = min(scaled.width, scaled.height)
        return scaled.cropping(to: CGRect(x: (scaled.width - crop) / 2, y: (scaled.height - crop) / 2, width: crop, height: crop))
    }
}
