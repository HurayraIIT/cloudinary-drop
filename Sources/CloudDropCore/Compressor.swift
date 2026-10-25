import Foundation
import Synchronization

public enum CompressionError: Error, LocalizedError, CustomStringConvertible {
    /// ffmpeg exited with an error. `output` is the end of what it printed, for the log.
    case failed(status: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case let .failed(status, _): "ffmpeg exited with status \(status)"
        }
    }

    public var description: String {
        switch self {
        case let .failed(status, output): "ffmpeg exited with status \(status): \(output)"
        }
    }
}

/// Runs the user's ffmpeg to compress one video (ADR 0008).
public enum Compressor {
    /// Writes the compressed MP4 to `output`. `progress` gets the fraction done, when the video's length is known.
    /// Cancelling the task stops ffmpeg and throws `CancellationError`.
    public static func compress(_ input: URL, to output: URL, quality: QualityLevel, ffmpeg: URL = Compression.ffmpegURL,
                                progress: @escaping @Sendable (Double) -> Void) async throws {
        let probe = await probe(input)
        let reader = CompressionProgress(duration: probe.duration).map { ProgressReader($0, report: progress) }
        let arguments = Compression.arguments(input: input, output: output, quality: quality, rotation: probe.rotation)
        try await run(ffmpeg, arguments) { chunk in
            reader?.read(chunk)
        }
    }

    /// The video's length and rotation. Both are unknown when ffprobe is missing or can't tell.
    static func probe(_ url: URL, ffprobe: URL = Compression.ffprobeURL) async -> VideoProbe {
        let output = Collected()
        guard (try? await run(ffprobe, VideoProbe.arguments(for: url), onOutput: output.append)) != nil else { return VideoProbe() }
        return VideoProbe(parsing: output.text)
    }

    /// The video's length in seconds, or nil when ffprobe is missing or can't tell.
    static func duration(of url: URL, ffprobe: URL = Compression.ffprobeURL) async -> Double? {
        await probe(url, ffprobe: ffprobe).duration
    }

    static func run(_ executable: URL, _ arguments: [String], onOutput: @escaping @Sendable (Data) -> Void) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let errors = Collected(keepingLast: 4096)
        stdout.fileHandleForReading.readabilityHandler = { onOutput($0.availableData) }
        stderr.fileHandleForReading.readabilityHandler = { errors.append($0.availableData) }

        let status: Int32 = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        onOutput(stdout.fileHandleForReading.readDataToEndOfFile())
        errors.append(stderr.fileHandleForReading.readDataToEndOfFile())
        try Task.checkCancellation()
        guard status == 0 else {
            throw CompressionError.failed(status: status, output: errors.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// Turns ffmpeg's `-progress` chunks, which arrive on a pipe's background queue, into fractions done.
private final class ProgressReader: Sendable {
    private let progress: Mutex<CompressionProgress>
    private let report: @Sendable (Double) -> Void

    init(_ progress: CompressionProgress, report: @escaping @Sendable (Double) -> Void) {
        self.progress = Mutex(progress)
        self.report = report
    }

    func read(_ chunk: Data) {
        let text = String(decoding: chunk, as: UTF8.self)
        if let fraction = progress.withLock({ $0.read(text) }) { report(fraction) }
    }
}

/// Output gathered from a pipe's background queue; optionally only the end of it.
private final class Collected: Sendable {
    private let data = Mutex(Data())
    private let limit: Int?

    init(keepingLast limit: Int? = nil) {
        self.limit = limit
    }

    func append(_ chunk: Data) {
        data.withLock { data in
            data.append(chunk)
            if let limit, data.count > limit { data = Data(data.suffix(limit)) }
        }
    }

    var text: String {
        data.withLock { String(decoding: $0, as: UTF8.self) }
    }
}
