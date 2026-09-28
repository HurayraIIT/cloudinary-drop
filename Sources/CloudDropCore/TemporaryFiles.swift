import Foundation

/// Names the temporary files Uploads need, so the ones left behind can be found and removed.
public enum TemporaryFiles {
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
}
