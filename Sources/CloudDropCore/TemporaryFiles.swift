import Foundation

/// Names the temporary files Uploads need, so the ones left behind can be found and removed,
/// and keeps Captures apart from them, because a Capture is the only copy and is never deleted unuploaded.
public enum TemporaryFiles: Sendable {
    static let prefix = "clouddrop-"
    static let dropsFolderName = "clouddrop-drops"
    static let capturesFolderName = "clouddrop-captures"
    static let compressedFolderName = "clouddrop-compressed"

    /// Where one Upload's multipart body is written before it is sent.
    public static func multipartBody(in directory: URL = FileManager.default.temporaryDirectory) -> URL {
        directory.appendingPathComponent("\(prefix)\(UUID().uuidString).multipart")
    }

    /// A fresh folder for a file a Drop hands over as a file promise.
    public static func dropFolder(in directory: URL = FileManager.default.temporaryDirectory) -> URL {
        directory.appendingPathComponent("\(dropsFolderName)/\(UUID().uuidString)", isDirectory: true)
    }

    /// A fresh folder a Capture is moved into while it waits in the Upload Queue, since macOS deletes
    /// the original when the drag ends.
    public static func captureFolder(in directory: URL = FileManager.default.temporaryDirectory) -> URL {
        directory.appendingPathComponent("\(capturesFolderName)/\(UUID().uuidString)", isDirectory: true)
    }

    /// Where ffmpeg writes one compressed video. The folder is created by the caller.
    public static func compressedVideo(in directory: URL = FileManager.default.temporaryDirectory) -> URL {
        directory.appendingPathComponent("\(compressedFolderName)/\(UUID().uuidString).mp4")
    }

    /// Whether a dropped file is a Capture: still in the `TemporaryItems` folder floating screenshot and
    /// screen recording thumbnails hand over, or already moved into a capture folder. A file the user
    /// dragged from `/tmp` or anywhere else in Finder is theirs and never counts.
    public static func isCapture(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.contains("/TemporaryItems/") || path.contains("/\(capturesFolderName)/")
    }

    /// What the sweep did with the Captures it found.
    public struct LeftoverCaptures: Equatable, Sendable {
        public var saved = 0
        /// Captures that couldn't be saved to Downloads. They stay where they are and are tried again at the next
        /// launch or quit, since each is the only copy.
        public var unsaved = 0
    }

    /// Removes multipart bodies, received Drop files and compressed videos, and saves any Capture still waiting
    /// to Downloads.
    /// Quitting mid-upload skips the `defer` that normally deletes a body, and a video's body can be 100 MB.
    /// A capture folder is only removed once it's empty, so a Capture that couldn't be saved is never deleted.
    @discardableResult
    public static func removeLeftovers(in directory: URL = FileManager.default.temporaryDirectory,
                                       downloads: URL = downloadsFolder) -> LeftoverCaptures {
        let fileManager = FileManager.default
        let captures = directory.appendingPathComponent(capturesFolderName)
        var result = LeftoverCaptures()
        for folder in (try? fileManager.contentsOfDirectory(at: captures, includingPropertiesForKeys: nil)) ?? [] {
            for file in (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                if saveToDownloads(file, in: downloads) != nil { result.saved += 1 } else { result.unsaved += 1 }
            }
            removeIfEmpty(folder)
        }
        if isEmpty(captures) { try? fileManager.removeItem(at: captures) }
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where [dropsFolderName, compressedFolderName].contains(name)
            || (name.hasPrefix(prefix) && name.hasSuffix(".multipart")) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
        return result
    }

    /// The Last Error after the sweep at launch: Captures left by a quit or crash that were saved to Downloads,
    /// and any that couldn't be. Nil when there were none.
    public static func leftoverCapturesMessage(_ captures: LeftoverCaptures) -> String? {
        switch (captures.saved, captures.unsaved) {
        case (0, 0): nil
        case let (saved, 0): capturesSavedMessage(count: saved)
        case let (0, unsaved):
            "Couldn't save \(unsaved) unfinished Capture\(unsaved == 1 ? "" : "s") to Downloads, will try again at next launch"
        case let (saved, unsaved):
            addingSentence("Couldn't save \(unsaved) more, will try again at next launch", to: capturesSavedMessage(count: saved))
        }
    }

    /// Moves a Capture out of `TemporaryItems` into its own capture folder straight away, because macOS deletes it
    /// when the drag ends. Returns where it is now: where it was if it couldn't be moved or copied, while it lasts.
    public static func keep(capture fileURL: URL, in directory: URL = FileManager.default.temporaryDirectory) -> URL {
        let folder = captureFolder(in: directory)
        let destination = folder.appendingPathComponent(fileURL.lastPathComponent)
        let fileManager = FileManager.default
        guard (try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
              (try? fileManager.moveItem(at: fileURL, to: destination)) != nil
                || (try? fileManager.copyItem(at: fileURL, to: destination)) != nil
        else { return fileURL }
        return destination
    }

    /// A Last Error that also says the Capture it's about was saved to Downloads.
    public static func mentioningCaptureSaved(_ message: String) -> String {
        message + (message.hasSuffix(".") ? " " : ". ") + "Saved to Downloads."
    }

    /// A Last Error that also says the Capture it's about couldn't be saved to Downloads. It stays in its capture
    /// folder, and the sweep at quit or the next launch tries again.
    public static func mentioningCaptureNotSaved(_ message: String) -> String {
        addingSentence("Couldn't save it to Downloads.", to: message)
    }

    /// The Last Error after Captures left by a quit or crash were saved to Downloads.
    public static func capturesSavedMessage(count: Int) -> String {
        "Saved \(count) unfinished Capture\(count == 1 ? "" : "s") to Downloads"
    }

    /// Deletes a received file or uploaded Capture, and its Drop or capture folder once that's empty.
    public static func remove(_ fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
        removeFolderIfEmpty(of: fileURL)
    }

    public static var downloadsFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    /// Moves a Capture that won't be uploaded, or a compressed video that was refused, to Downloads as
    /// `cd-<filename>`, adding ` 2`, ` 3`… rather than overwrite. Nil when the file is missing or can't be
    /// moved or copied.
    @discardableResult
    public static func saveToDownloads(_ sourceURL: URL, filename: String? = nil,
                                              in downloads: URL = downloadsFolder) -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else { return nil }
        try? fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)

        let name = filename ?? sourceURL.lastPathComponent
        let prefixedName = name.hasPrefix("cd-") ? name : "cd-\(name)"
        let ext = (prefixedName as NSString).pathExtension
        let base = (prefixedName as NSString).deletingPathExtension

        var destination = downloads.appendingPathComponent(prefixedName)
        var counter = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = downloads.appendingPathComponent(ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
            counter += 1
        }

        if (try? fileManager.moveItem(at: sourceURL, to: destination)) == nil {
            guard (try? fileManager.copyItem(at: sourceURL, to: destination)) != nil else { return nil }
            try? fileManager.removeItem(at: sourceURL)
        }
        removeFolderIfEmpty(of: sourceURL)
        return destination
    }

    private static func removeFolderIfEmpty(of fileURL: URL) {
        removeIfEmpty(fileURL.deletingLastPathComponent())
    }

    /// Only ever a per-file folder inside `clouddrop-drops` or `clouddrop-captures`, never anything of the user's.
    private static func removeIfEmpty(_ folder: URL) {
        guard [dropsFolderName, capturesFolderName].contains(folder.deletingLastPathComponent().lastPathComponent),
              isEmpty(folder)
        else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// False when the folder can't be read, so it's never removed by mistake.
    private static func isEmpty(_ folder: URL) -> Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? ["?"]).isEmpty
    }
}
