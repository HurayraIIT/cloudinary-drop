import Foundation

/// A file's place in the Upload Queue, kept for it while it's still arriving from a file promise, with the
/// Compression setting read when its Drop was accepted.
public struct UploadPlace: Sendable {
    let number: Int
    public let compression: CompressionSetting
}

/// The Upload Queue's order. A file from a file promise gets its place when the Drop is accepted, not when it
/// arrives, so files keep their drop order and a later Drop stays behind it. The queue waits at a place until
/// its file is received, or until it's released because receiving it failed or it was refused.
public struct UploadOrder<Job> {
    private var slots: [(number: Int, job: Job?)] = []
    private var lastNumber = 0

    public init() {}

    public var isEmpty: Bool { slots.isEmpty }

    /// Whether the front of the queue is ready to start, rather than still arriving.
    public var hasNext: Bool { slots.first?.job != nil }

    /// Adds a file that's already on disk at the end.
    public mutating func append(_ job: Job) {
        lastNumber += 1
        slots.append((lastNumber, job))
    }

    /// Keeps a place at the end for a file that hasn't arrived yet.
    public mutating func reserve(compression: CompressionSetting) -> UploadPlace {
        lastNumber += 1
        slots.append((lastNumber, nil))
        return UploadPlace(number: lastNumber, compression: compression)
    }

    /// Puts an arrived file in its place. A place that's gone or already taken (a promise that delivered a
    /// second file) adds it at the end instead, so it's never lost.
    public mutating func fill(_ place: UploadPlace, with job: Job) {
        guard let index = slots.firstIndex(where: { $0.number == place.number && $0.job == nil }) else {
            return append(job)
        }
        slots[index].job = job
    }

    /// Gives up a place whose file won't arrive, so the files behind it can go. A place already filled is kept.
    public mutating func release(_ place: UploadPlace) {
        slots.removeAll { $0.number == place.number && $0.job == nil }
    }

    /// Takes the job at the front, or nil when the queue is empty or its front is still arriving.
    public mutating func next() -> Job? {
        guard let job = slots.first?.job else { return nil }
        slots.removeFirst()
        return job
    }
}
