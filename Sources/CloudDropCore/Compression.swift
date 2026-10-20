import Foundation

/// How much sharpness Compression may give up for a smaller file. The raw value is x264's CRF.
public enum QualityLevel: Int, CaseIterable, Sendable {
    case crf22 = 22
    case crf24 = 24
    case crf26 = 26

    public static let `default` = QualityLevel.crf22

    public var menuTitle: String {
        switch self {
        case .crf22: "CRF 22 · Best quality"
        case .crf24: "CRF 24"
        case .crf26: "CRF 26 · Smallest files"
        }
    }
}

/// Whether the videos in a Drop are compressed. It's read when the Drop happens, so changing the menu
/// never affects a video already dropped.
public enum CompressionSetting: Equatable, Sendable {
    case on(QualityLevel)
    case off
    case noFFmpeg

    public init(isFFmpegInstalled: Bool, isEnabled: Bool, quality: QualityLevel) {
        self = !isFFmpegInstalled ? .noFFmpeg : isEnabled ? .on(quality) : .off
    }

    public var isOn: Bool {
        if case .on = self { true } else { false }
    }

    /// Ends the message for a video refused for its size without being compressed.
    var sizeRefusalHint: String? {
        switch self {
        case .on: nil
        case .off: "Turn on Compress Videos to fit it."
        case .noFFmpeg: "Install ffmpeg to compress it."
        }
    }
}

/// Compressing a video before its Upload, with the user's Homebrew ffmpeg (ADR 0008).
public enum Compression {
    /// A GUI app doesn't get the shell's PATH, so Homebrew's location is looked up directly.
    public static let ffmpegURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    /// Installed with ffmpeg. Only used to read a video's length for the progress percentage.
    public static let ffprobeURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
    /// Recordings that don't fit within this square are scaled down, keeping their aspect ratio.
    static let maxSide = 1920

    public static func isFFmpegInstalled(at url: URL = ffmpegURL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    /// The fixed pipeline, tuned for the fanless M1 Air: decoding and scaling on the GPU, then x264 on two threads.
    /// The scale always runs, so odd sizes are rounded down to even ones, which x264 needs; it keeps the size
    /// otherwise. `-noautorotate` keeps a phone video's rotation as metadata, because rotating needs CPU frames.
    public static func arguments(input: URL, output: URL, quality: QualityLevel) -> [String] {
        let fit = "min(1\\,\(maxSide)/max(iw\\,ih))"
        let scale = "scale_vt=w='trunc(iw*\(fit)/2)*2':h='trunc(ih*\(fit)/2)*2'"
        return [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-noautorotate", "-hwaccel", "videotoolbox", "-hwaccel_output_format", "videotoolbox_vld",
            "-i", input.path,
            "-vf", "\(scale),hwdownload,format=nv12", "-fpsmax", "30",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "\(quality.rawValue)", "-threads", "2", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "96k", "-sn", "-dn",
            "-movflags", "+faststart",
            "-progress", "pipe:1", "-nostats",
            output.path,
        ]
    }

    /// The `display_name` of a compressed video, matching its Share Link: `rec.mov` becomes `rec.mp4`.
    public static func compressedFilename(_ filename: String) -> String {
        (filename as NSString).deletingPathExtension + ".mp4"
    }

    /// What a refused video is saved to Downloads as, before the `cd-` prefix:
    /// `rec (original).mov`, or `rec (compressed).mp4`.
    public static func downloadsName(_ filename: String, compressed: Bool) -> String {
        let base = (filename as NSString).deletingPathExtension
        let ext = compressed ? "mp4" : (filename as NSString).pathExtension
        let name = "\(base) (\(compressed ? "compressed" : "original"))"
        return ext.isEmpty ? name : "\(name).\(ext)"
    }

    /// The Last Error after ffmpeg failed and the original was uploaded instead.
    public static func uploadedUncompressedMessage(filename: String) -> String {
        "Couldn't compress \(filename), uploaded it as is"
    }

    /// Ends the message for a video refused for its size after ffmpeg failed to compress it.
    public static let failedHint = "Couldn't compress it."
}

/// Reads ffmpeg's `-progress` output, which arrives in chunks that can split a line.
public struct CompressionProgress: Sendable {
    private let duration: Double
    private var partialLine = ""

    /// Nil when the video's length is unknown, so no percentage can be shown.
    public init?(duration: Double?) {
        guard let duration, duration > 0 else { return nil }
        self.duration = duration
    }

    /// The latest fraction done in this chunk, if it had one.
    public mutating func read(_ chunk: String) -> Double? {
        let lines = (partialLine + chunk).split(separator: "\n", omittingEmptySubsequences: false)
        partialLine = String(lines.last ?? "")
        var latest: Double?
        for line in lines.dropLast() where line.hasPrefix("out_time_us=") {
            guard let microseconds = Double(line.dropFirst("out_time_us=".count)) else { continue }
            latest = min(1, max(0, microseconds / 1_000_000 / duration))
        }
        return latest
    }
}

/// Joins a follow-up sentence onto a Last Error.
public func addingSentence(_ sentence: String, to message: String) -> String {
    message + (message.hasSuffix(".") ? " " : ". ") + sentence
}
