import Foundation

/// Names the temporary files Uploads need, so the ones left behind can be found and removed.
public enum TemporaryFiles: Sendable {
    static let prefix = "clouddrop-"
    static let dropsFolderName = "clouddrop-drops"

    /// Where one Upload's multipart body is written before it is sent.
    public static func multipartBody(in directory: URL = FileManager.default.temporaryDirectory) -> URL {
        directory.appendingPathComponent("\(prefix)\(UUID().uuidString).multipart")
    }

    /// A fresh folder for the files a Drop hands over as file promises.
    public static func dropFolder(in directory: URL = FileManager.default.temporaryDirectory) -> URL {
        directory.appendingPathComponent("\(dropsFolderName)/\(UUID().uuidString)", isDirectory: true)
    }

    /// Removes multipart bodies and received Drop files. Quitting mid-upload skips the `defer`
    /// that normally deletes a body, and a video's body can be 100 MB.
    public static func removeLeftovers(in directory: URL = FileManager.default.temporaryDirectory) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name == dropsFolderName || (name.hasPrefix(prefix) && name.hasSuffix(".multipart")) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Moves a temporary file (such as one received from an NSFilePromiseReceiver) to the Downloads
    /// folder so that refused files or failed uploads are never lost.
    /// Prefixes the filename with 'cd-' and avoids overwriting existing files by appending a counter.
    @discardableResult
    public static func preserveTemporaryFile(
        at sourceURL: URL,
        originalFilename: String? = nil,
        in destinationDirectory: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    ) -> URL? {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return nil }

        try? FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let filename = originalFilename ?? sourceURL.lastPathComponent
        let prefixedName = filename.hasPrefix("cd-") ? filename : "cd-\(filename)"
        let ext = (prefixedName as NSString).pathExtension
        let base = (prefixedName as NSString).deletingPathExtension

        var destinationURL = destinationDirectory.appendingPathComponent(prefixedName)
        var counter = 2
        while FileManager.default.fileExists(atPath: destinationURL.path) {
            let candidateName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            destinationURL = destinationDirectory.appendingPathComponent(candidateName)
            counter += 1
        }

        do {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            cleanupParentDropFolder(of: sourceURL)
            return destinationURL
        } catch {
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                try? FileManager.default.removeItem(at: sourceURL)
                cleanupParentDropFolder(of: sourceURL)
                return destinationURL
            } catch {
                return nil
            }
        }
    }

    private static func cleanupParentDropFolder(of fileURL: URL) {
        let parent = fileURL.deletingLastPathComponent()
        guard parent.lastPathComponent != dropsFolderName && parent.path.contains(dropsFolderName) else { return }
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        if siblings.isEmpty {
            try? FileManager.default.removeItem(at: parent)
        }
    }
}
