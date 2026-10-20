import CloudDropCore
import Foundation

/// The menu's Compress Videos toggle and Quality Level, saved on this Mac only (ADR 0008).
@MainActor
enum VideoCompression {
    private static let enabledKey = "compressVideos"
    private static let qualityKey = "videoQualityLevel"

    /// On by default.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var quality: QualityLevel {
        get { QualityLevel(rawValue: UserDefaults.standard.integer(forKey: qualityKey)) ?? .default }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: qualityKey) }
    }

    /// Looks for ffmpeg every time, so installing it while CloudDrop runs needs no restart.
    static var setting: CompressionSetting {
        CompressionSetting(isFFmpegInstalled: Compression.isFFmpegInstalled(), isEnabled: isEnabled, quality: quality)
    }
}
