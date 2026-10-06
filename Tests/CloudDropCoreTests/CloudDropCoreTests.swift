import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CloudDropCore

@Suite struct CloudinaryURLParsing {
    @Test func parsesPlainURL() {
        let credentials = CloudinaryCredentials(parsing: "cloudinary://123:abc-DEF_456@djasqoair")
        #expect(credentials == CloudinaryCredentials(apiKey: "123", apiSecret: "abc-DEF_456", cloudName: "djasqoair"))
    }

    @Test func acceptsAPastedShellLine() {
        let credentials = CloudinaryCredentials(parsing: "  export CLOUDINARY_URL=\"cloudinary://123:abc@djasqoair\"\n")
        #expect(credentials?.cloudName == "djasqoair")
        #expect(credentials?.apiSecret == "abc")
    }

    @Test func ignoresQueryAfterCloudName() {
        #expect(CloudinaryCredentials(parsing: "cloudinary://1:2@mycloud?secure=true")?.cloudName == "mycloud")
    }

    @Test(arguments: [
        "", "https://123:abc@djasqoair", "cloudinary://123abc@djasqoair",
        "cloudinary://:abc@djasqoair", "cloudinary://123:@djasqoair", "cloudinary://123:abc@",
        "cloudinary://123:a b@djasqoair",
    ])
    func rejectsMalformed(_ raw: String) {
        #expect(CloudinaryCredentials(parsing: raw) == nil)
    }

    @Test func roundTrips() {
        let raw = "cloudinary://123:abc@djasqoair"
        #expect(CloudinaryCredentials(parsing: raw)?.urlString == raw)
    }
}

@Suite struct PublicIDNaming {
    @Test func nameGoesInTheShortFolder() {
        #expect(PublicID.make(name: "k3f9x2ab") == "d/k3f9x2ab")
    }

    @Test func randomNameIsEightSafeCharacters() {
        let name = PublicID.randomName()
        #expect(name.count == 8)
        #expect(name.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) })
    }

    @Test func randomNamesDiffer() {
        #expect(Set((0..<100).map { _ in PublicID.randomName() }).count == 100)
    }
}

@Suite struct Signing {
    @Test func matchesCloudinaryDocumentationExample() {
        let params = ["eager": "w_400,h_300,c_pad|w_260,h_200,c_crop", "public_id": "sample_image", "timestamp": "1315060510"]
        #expect(uploadSignature(params, secret: "abcd") == "bfd09f95f331f558cbd1320e67aa8d488770583e")
    }

    @Test func signsOurUploadParametersInSortedOrder() {
        let params = [
            "timestamp": "1790000000",
            "public_id": "d/k3f9x2ab",
            "overwrite": "false",
            "display_name": "Screenshot 2026-09-29 at 12.31.45.png",
            "asset_folder": "clouddrop",
        ]
        #expect(uploadSignature(params, secret: "secret123") == "7c33e9d1db84482f9f8fa9a2621a0245e03c35e2")
    }
}

@Suite struct MediaFiles {
    @Test(arguments: ["png", "jpg", "heic", "gif", "webp", "PNG"])
    func imagesAreImages(_ ext: String) {
        #expect(MediaKind(fileExtension: ext) == .image)
    }

    @Test(arguments: ["mov", "mp4", "m4v"])
    func videosAreVideos(_ ext: String) {
        #expect(MediaKind(fileExtension: ext) == .video)
    }

    @Test(arguments: ["pdf", "zip", "txt", "mp3"])
    func othersAreRefused(_ ext: String) {
        #expect(MediaKind(fileExtension: ext) == nil)
    }

    @Test func imageAtLimitIsAccepted() {
        #expect(checkMediaFile(filename: "a.png", type: .png, byteCount: 10_485_760) == .success(.image))
    }

    @Test func imageOverLimitIsRefused() {
        let result = checkMediaFile(filename: "raw.png", type: .png, byteCount: 14_680_064)
        #expect(result == .failure(.tooLarge(filename: "raw.png", kind: .image, byteCount: 14_680_064)))
        #expect(Refusal.tooLarge(filename: "raw.png", kind: .image, byteCount: 14_680_064).message
            == "raw.png is 14 MB, image limit is 10 MB")
    }

    @Test func largeVideoUnderVideoLimitIsAccepted() {
        #expect(checkMediaFile(filename: "rec.mov", type: .quickTimeMovie, byteCount: 40_000_000) == .success(.video))
    }

    @Test func videoOverLimitMessage() {
        #expect(Refusal.tooLarge(filename: "rec.mov", kind: .video, byteCount: 262_144_000).message
            == "rec.mov is 250 MB, video limit is 100 MB")
        #expect(megabytes(11_010_048) == "10.5 MB")
    }

    @Test func nonMediaIsRefused() {
        #expect(checkMediaFile(filename: "notes.pdf", type: .pdf, byteCount: 1000) == .failure(.notMedia(filename: "notes.pdf")))
        #expect(checkMediaFile(filename: "folder", type: nil, byteCount: 0) == .failure(.notMedia(filename: "folder")))
        #expect(Refusal.notMedia(filename: "notes.pdf").message == "notes.pdf isn't an image or video")
    }

    @Test func unknownSizeIsRefusedNotWavedThrough() {
        #expect(checkMediaFile(filename: "a.png", type: .png, byteCount: nil) == .failure(.unreadable(filename: "a.png")))
        #expect(Refusal.unreadable(filename: "a.png").message == "a.png couldn't be read")
    }
}

@Suite struct UploadResponses {
    private func body(_ json: String) -> Data { Data(json.utf8) }

    @Test func successReturnsWhatWasStored() throws {
        let file = try Uploader.uploadedFile(status: 200, data: body(#"{"public_id":"d/k3f9x2ab","format":"png","secure_url":"https://res.cloudinary.com/c/image/upload/v1/d/k3f9x2ab.png"}"#))
        #expect(file == UploadedFile(publicID: "d/k3f9x2ab", format: "png"))
    }

    @Test func takenNameIsAFailureNotTheOldFile() {
        #expect(throws: UploadError.nameTaken(publicID: "d/k3f9x2ab")) {
            try Uploader.uploadedFile(status: 200, data: body(#"{"public_id":"d/k3f9x2ab","format":"png","existing":true}"#))
        }
        let error: any Error = UploadError.nameTaken(publicID: "d/k3f9x2ab")
        #expect(error.localizedDescription == "Its random name was already taken, drop it again")
        #expect(String(describing: error).contains("d/k3f9x2ab"))
    }

    @Test func freshUploadMarkedNotExistingSucceeds() throws {
        let file = try Uploader.uploadedFile(status: 200, data: body(#"{"public_id":"d/k3f9x2ab","format":"mov","existing":false}"#))
        #expect(file.format == "mov")
    }

    @Test func keepsCloudinarysUploadTime() throws {
        let file = try Uploader.uploadedFile(status: 200, data: body(#"{"public_id":"d/k3f9x2ab","format":"png","created_at":"2026-09-30T06:44:46Z"}"#))
        #expect(file.createdAt == Date(timeIntervalSince1970: 1_790_750_686))
    }

    @Test func keepsTheStoredSize() throws {
        let file = try Uploader.uploadedFile(status: 200, data: body(#"{"public_id":"d/k3f9x2ab","format":"heic","bytes":2483017}"#))
        #expect(file.byteCount == 2_483_017)
        #expect(try Uploader.uploadedFile(status: 200, data: body(#"{"public_id":"d/k3f9x2ab","format":"png"}"#)).byteCount == nil)
    }

    @Test func successWithoutPublicIDIsUnexpected() {
        #expect(throws: UploadError.unexpectedResponse(200)) {
            try Uploader.uploadedFile(status: 200, data: body(#"{"secure_url":"https://res.cloudinary.com/c/image/upload/v1/d/x.png"}"#))
        }
    }

    @Test func forbiddenKeepsCloudinaryMessageForTheLog() {
        let raw = #"missing permissions (actions=["create"])"#
        #expect(throws: UploadError.notAllowedToUpload(cloudinaryMessage: raw)) {
            try Uploader.uploadedFile(status: 403, data: body(#"{"error":{"message":"missing permissions (actions=[\"create\"])"}}"#))
        }
        let error: any Error = UploadError.notAllowedToUpload(cloudinaryMessage: raw)
        #expect(error.localizedDescription.contains("isn't allowed to upload"))
        #expect(!error.localizedDescription.contains(raw))
        #expect(String(describing: error).contains(raw))
    }

    @Test func otherErrorsShowCloudinaryMessageAndStatus() {
        #expect(throws: UploadError.cloudinary("Invalid image file (HTTP 400)")) {
            try Uploader.uploadedFile(status: 400, data: body(#"{"error":{"message":"Invalid image file"}}"#))
        }
    }

    @Test func unreadableAnswerReportsStatus() {
        #expect(throws: UploadError.unexpectedResponse(502)) {
            try Uploader.uploadedFile(status: 502, data: body("<html>Bad gateway</html>"))
        }
    }
}

@Suite struct Thumbnails {
    private func writePNG(width: Int, height: Int) throws -> URL {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clouddrop-tests-\(UUID().uuidString).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test(arguments: [(300, 100), (100, 300), (500, 500)])
    func cropsToASquareOfTheRequestedSide(_ size: (Int, Int)) throws {
        let url = try writePNG(width: size.0, height: size.1)
        defer { try? FileManager.default.removeItem(at: url) }
        let thumbnail = try #require(Thumbnail.make(imageAt: url, side: 44))
        #expect(thumbnail.width == 44)
        #expect(thumbnail.height == 44)
    }

    @Test func nonImageHasNoThumbnail() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clouddrop-tests-\(UUID().uuidString).png")
        try Data("not an image".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(Thumbnail.make(imageAt: url, side: 44) == nil)
    }
}

@Suite struct TemporaryFileCleanup {
    @Test func removesOnlyCloudDropLeftovers() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("clouddrop-tests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let body = TemporaryFiles.multipartBody(in: directory)
        let dropFolder = TemporaryFiles.dropFolder(in: directory)
        try fileManager.createDirectory(at: dropFolder, withIntermediateDirectories: true)
        let kept = ["other.multipart", "clouddrop-notes.txt"]
        for file in [body, dropFolder.appendingPathComponent("shot.png")] + kept.map(directory.appendingPathComponent) {
            try Data("x".utf8).write(to: file)
        }

        TemporaryFiles.removeLeftovers(in: directory)

        #expect(try fileManager.contentsOfDirectory(atPath: directory.path).sorted() == kept.sorted())
    }

    @Test func preservesTemporaryFileWithPrefix() throws {
        let fileManager = FileManager.default
        let baseDir = fileManager.temporaryDirectory.appendingPathComponent("clouddrop-tests-\(UUID().uuidString)")
        let dropFolder = TemporaryFiles.dropFolder(in: baseDir)
        let downloads = baseDir.appendingPathComponent("Downloads")
        try fileManager.createDirectory(at: dropFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: baseDir) }

        let file = dropFolder.appendingPathComponent("recording.mov")
        try Data("test content".utf8).write(to: file)

        let saved = TemporaryFiles.preserveTemporaryFile(at: file, originalFilename: "recording.mov", in: downloads)
        #expect(saved == downloads.appendingPathComponent("cd-recording.mov"))
        #expect(fileManager.fileExists(atPath: downloads.appendingPathComponent("cd-recording.mov").path))
        #expect(!fileManager.fileExists(atPath: file.path))
        #expect(!fileManager.fileExists(atPath: dropFolder.path))
    }

    @Test func preservesSiblingFilesInDropFolder() throws {
        let fileManager = FileManager.default
        let baseDir = fileManager.temporaryDirectory.appendingPathComponent("clouddrop-tests-\(UUID().uuidString)")
        let dropFolder = TemporaryFiles.dropFolder(in: baseDir)
        let downloads = baseDir.appendingPathComponent("Downloads")
        try fileManager.createDirectory(at: dropFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: baseDir) }

        let file1 = dropFolder.appendingPathComponent("recording1.mov")
        let file2 = dropFolder.appendingPathComponent("recording2.mov")
        try Data("content1".utf8).write(to: file1)
        try Data("content2".utf8).write(to: file2)

        TemporaryFiles.preserveTemporaryFile(at: file1, originalFilename: "recording1.mov", in: downloads)
        #expect(fileManager.fileExists(atPath: downloads.appendingPathComponent("cd-recording1.mov").path))
        #expect(fileManager.fileExists(atPath: file2.path))
        #expect(fileManager.fileExists(atPath: dropFolder.path))

        TemporaryFiles.preserveTemporaryFile(at: file2, originalFilename: "recording2.mov", in: downloads)
        #expect(fileManager.fileExists(atPath: downloads.appendingPathComponent("cd-recording2.mov").path))
        #expect(!fileManager.fileExists(atPath: file2.path))
        #expect(!fileManager.fileExists(atPath: dropFolder.path))
    }

    @Test func preservesTemporaryFileWithoutDuplicatingPrefix() throws {
        let fileManager = FileManager.default
        let baseDir = fileManager.temporaryDirectory.appendingPathComponent("clouddrop-tests-\(UUID().uuidString)")
        let dropFolder = TemporaryFiles.dropFolder(in: baseDir)
        let downloads = baseDir.appendingPathComponent("Downloads")
        try fileManager.createDirectory(at: dropFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: baseDir) }

        let file = dropFolder.appendingPathComponent("cd-already.mov")
        try Data("test".utf8).write(to: file)

        let saved = TemporaryFiles.preserveTemporaryFile(at: file, originalFilename: "cd-already.mov", in: downloads)
        #expect(saved == downloads.appendingPathComponent("cd-already.mov"))
        #expect(fileManager.fileExists(atPath: downloads.appendingPathComponent("cd-already.mov").path))
    }

    @Test func resolvesCollisionsWithCounter() throws {
        let fileManager = FileManager.default
        let baseDir = fileManager.temporaryDirectory.appendingPathComponent("clouddrop-tests-\(UUID().uuidString)")
        let dropFolder = TemporaryFiles.dropFolder(in: baseDir)
        let downloads = baseDir.appendingPathComponent("Downloads")
        try fileManager.createDirectory(at: dropFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: baseDir) }

        try Data("1".utf8).write(to: downloads.appendingPathComponent("cd-video.mov"))
        try Data("2".utf8).write(to: downloads.appendingPathComponent("cd-video 2.mov"))

        let file = dropFolder.appendingPathComponent("video.mov")
        try Data("3".utf8).write(to: file)

        let saved = TemporaryFiles.preserveTemporaryFile(at: file, originalFilename: "video.mov", in: downloads)
        #expect(saved == downloads.appendingPathComponent("cd-video 3.mov"))
        #expect(fileManager.fileExists(atPath: downloads.appendingPathComponent("cd-video 3.mov").path))
    }

    @Test func resolvesCollisionsForFilesWithoutExtension() throws {
        let fileManager = FileManager.default
        let baseDir = fileManager.temporaryDirectory.appendingPathComponent("clouddrop-tests-\(UUID().uuidString)")
        let dropFolder = TemporaryFiles.dropFolder(in: baseDir)
        let downloads = baseDir.appendingPathComponent("Downloads")
        try fileManager.createDirectory(at: dropFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: baseDir) }

        try Data("1".utf8).write(to: downloads.appendingPathComponent("cd-recording"))

        let file = dropFolder.appendingPathComponent("recording")
        try Data("2".utf8).write(to: file)

        let saved = TemporaryFiles.preserveTemporaryFile(at: file, originalFilename: "recording", in: downloads)
        #expect(saved == downloads.appendingPathComponent("cd-recording 2"))
        #expect(fileManager.fileExists(atPath: downloads.appendingPathComponent("cd-recording 2").path))
    }

    @Test func returnsNilForNonExistentFile() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent-\(UUID().uuidString).mov")
        #expect(TemporaryFiles.preserveTemporaryFile(at: file) == nil)
    }
}

@Suite struct ShareLinks {
    @Test func imageUsesTheRootPathWithoutVersion() {
        #expect(ShareLink.make(cloudName: "djasqoair", kind: .image, file: UploadedFile(publicID: "d/k3f9x2ab", format: "png")).absoluteString
            == "https://res.cloudinary.com/djasqoair/d/k3f9x2ab.png")
    }

    @Test func videoKeepsItsTypeButNoVersion() {
        #expect(ShareLink.make(cloudName: "djasqoair", kind: .video, file: UploadedFile(publicID: "d/k3f9x2ab", format: "mov")).absoluteString
            == "https://res.cloudinary.com/djasqoair/video/upload/d/k3f9x2ab.mov")
    }

    @Test(arguments: ["heic", "HEIC", "heif"])
    func heicIsDeliveredAsJPEG(_ format: String) {
        #expect(ShareLink.make(cloudName: "djasqoair", kind: .image, file: UploadedFile(publicID: "d/k3f9x2ab", format: format)).absoluteString
            == "https://res.cloudinary.com/djasqoair/d/k3f9x2ab.jpg")
    }
}

@Suite struct MenuLabels {
    @Test func shortNamesAreKept() {
        #expect(MenuText.truncateMiddle("shot.png") == "shot.png")
    }

    @Test func longNamesKeepStartAndExtension() {
        let label = MenuText.truncateMiddle("Screenshot 2026-09-28 at 14.15.03.png")
        #expect(label.count == 30)
        #expect(label.hasPrefix("Screenshot 202"))
        #expect(label.hasSuffix("14.15.03.png"))
        #expect(label.contains("…"))
    }

    @Test(arguments: [
        (Int64(0), "0 KB"),
        (300, "1 KB"),
        (870_400, "850 KB"),
        (1_047_552, "1023 KB"),
        (1_048_575, "1.0 MB"),
        (4_404_019, "4.2 MB"),
        (10_433_331, "9.9 MB"),
        (10_433_332, "10 MB"),
        (10_485_760, "10 MB"),
        (91_226_112, "87 MB"),
        (104_857_600, "100 MB"),
    ])
    func fileSizesUseTheSizeLimitsUnits(_ bytes: Int64, _ label: String) {
        #expect(MenuText.fileSize(bytes) == label)
    }
}

@Suite struct LinkHistorySearch {
    private let credentials = CloudinaryCredentials(apiKey: "123", apiSecret: "abc", cloudName: "djasqoair")

    private func entries(_ json: String, status: Int = 200, reset: String? = nil) throws -> [HistoryEntry] {
        try HistorySearch.entries(status: status, data: Data(json.utf8), rateLimitReset: reset, cloudName: "djasqoair")
    }

    private func entry(_ id: String, at seconds: TimeInterval) -> HistoryEntry {
        HistoryEntry(publicID: id, kind: .image, filename: "\(id).png", uploadedAt: Date(timeIntervalSince1970: seconds),
                     shareLink: URL(string: "https://res.cloudinary.com/djasqoair/\(id).png")!)
    }

    @Test func searchesTheCloudDropFolderNewestFirst() throws {
        let request = HistorySearch.request(credentials: credentials, limit: 10)
        #expect(request.url?.absoluteString == "https://api.cloudinary.com/v1_1/djasqoair/resources/search")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic MTIzOmFiYw==")
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["expression"] as? String == "asset_folder=clouddrop")
        #expect(body["sort_by"] as? [[String: String]] == [["created_at": "desc"]])
        #expect(body["max_results"] as? Int == 10)
        #expect((body["fields"] as? [String])?.contains("bytes") == true)
    }

    @Test func readsImagesAndVideosIntoShareLinks() throws {
        let list = try entries(#"""
        {"total_count":3,"resources":[
          {"public_id":"d/gqpnfwdn","format":"png","resource_type":"image","created_at":"2026-09-30T06:44:46Z","display_name":"SCR-20260930-llhf.png","bytes":431208},
          {"public_id":"d/l8vo1m5o","format":"mov","resource_type":"video","created_at":"2026-09-29T17:20:41Z","display_name":"Screen Recording.mov"},
          {"public_id":"clouddrop/260928_101500_ab12_shot","format":"heic","resource_type":"image","created_at":"2026-09-28T10:15:00Z","display_name":""}
        ]}
        """#)
        #expect(list.map(\.shareLink.absoluteString) == [
            "https://res.cloudinary.com/djasqoair/d/gqpnfwdn.png",
            "https://res.cloudinary.com/djasqoair/video/upload/d/l8vo1m5o.mov",
            "https://res.cloudinary.com/djasqoair/clouddrop/260928_101500_ab12_shot.jpg",
        ])
        #expect(list.map(\.kind) == [.image, .video, .image])
        #expect(list[0].uploadedAt == Date(timeIntervalSince1970: 1_790_750_686))
        #expect(list[0].filename == "SCR-20260930-llhf.png")
        #expect(list[2].filename == "260928_101500_ab12_shot", "an empty display_name falls back to the public_id's last part")
        #expect(list[0].byteCount == 431_208)
        #expect(list[1].byteCount == nil, "a missing size stays unknown, never zero")
    }

    @Test func skipsAnythingThatIsntAnImageOrVideo() throws {
        let list = try entries(#"{"resources":[{"public_id":"d/notes","format":"txt","resource_type":"raw","created_at":"2026-09-30T06:44:46Z"}]}"#)
        #expect(list.isEmpty)
    }

    @Test func forbiddenMeansTheKeyCantList() {
        #expect(throws: HistoryFetchError.notAllowedToList(cloudinaryMessage: "missing permissions")) {
            try entries(#"{"error":{"message":"missing permissions"}}"#, status: 403)
        }
    }

    @Test(arguments: [420, 429])
    func rateLimitSaysWhenItResets(_ status: Int) {
        #expect(throws: HistoryFetchError.rateLimited(until: Date(timeIntervalSince1970: 1_790_751_600))) {
            try entries(#"{"error":{"message":"Rate Limit Exceeded"}}"#, status: status, reset: "Wed, 30 Sep 2026 07:00:00 GMT")
        }
        #expect(throws: HistoryFetchError.rateLimited(until: nil)) {
            try entries("{}", status: status)
        }
    }

    @Test func otherFailures() {
        #expect(throws: HistoryFetchError.cloudinary("Cloudinary rejected the API key or secret")) { try entries("{}", status: 401) }
        #expect(throws: HistoryFetchError.cloudinary("Bad expression (HTTP 400)")) {
            try entries(#"{"error":{"message":"Bad expression"}}"#, status: 400)
        }
        #expect(throws: HistoryFetchError.unexpectedResponse(502)) { try entries("<html>", status: 502) }
        #expect(throws: HistoryFetchError.unexpectedResponse(200)) { try entries("{}") }
    }

    @Test func ownUploadShowsBeforeSearchListsIt() {
        let fetched = [entry("d/old", at: 100)]
        let mine = [entry("d/new", at: 200)]
        #expect(HistorySearch.combine(fetched: fetched, unconfirmed: mine).map(\.publicID) == ["d/new", "d/old"])
    }

    @Test func combinedListIsSortedDeduplicatedAndCapped() {
        let fetched = (0..<10).map { entry("d/f\($0)", at: TimeInterval(1000 - $0 * 10)) }
        let mine = [entry("d/f3", at: 970), entry("d/mine", at: 955)]
        let combined = HistorySearch.combine(fetched: fetched, unconfirmed: mine)
        #expect(combined.count == 10)
        #expect(combined.map(\.publicID).filter { $0 == "d/f3" }.count == 1)
        #expect(combined[5].publicID == "d/mine")
        #expect(combined.last?.publicID == "d/f8")
    }

    @Test func ownUploadIsDroppedOnceSearchListsIt() {
        let mine = [entry("d/new", at: 200)]
        #expect(HistorySearch.stillUnconfirmed(mine, fetched: [entry("d/new", at: 200)], fetchStartedAt: Date(timeIntervalSince1970: 205)).isEmpty)
    }

    @Test func ownUploadWaitsForSearchToCatchUpButNotForever() {
        let mine = [entry("d/new", at: 200)]
        #expect(HistorySearch.stillUnconfirmed(mine, fetched: [], fetchStartedAt: Date(timeIntervalSince1970: 205)) == mine)
        #expect(HistorySearch.stillUnconfirmed(mine, fetched: [], fetchStartedAt: Date(timeIntervalSince1970: 200 + 121)).isEmpty)
    }

    @Test func deletedEntriesAreHiddenAndNotReplacedFromUnconfirmed() {
        let fetched = (0..<10).map { entry("d/f\($0)", at: TimeInterval(1000 - $0 * 10)) }
        let mine = [entry("d/mine", at: 2000)]
        let combined = HistorySearch.combine(fetched: fetched, unconfirmed: mine, deleted: ["d/f0", "d/mine"])
        #expect(combined.map(\.publicID) == (1..<10).map { "d/f\($0)" })
    }

    @Test func deletedStaysHiddenWhileSearchStillListsItButNotForever() {
        let deleted = ["d/gone": Date(timeIntervalSince1970: 200)]
        let listed = [entry("d/gone", at: 100)]
        #expect(HistorySearch.stillDeleted(deleted, fetched: listed, fetchStartedAt: Date(timeIntervalSince1970: 205)) == deleted)
        #expect(HistorySearch.stillDeleted(deleted, fetched: [], fetchStartedAt: Date(timeIntervalSince1970: 205)).isEmpty)
        #expect(HistorySearch.stillDeleted(deleted, fetched: listed, fetchStartedAt: Date(timeIntervalSince1970: 200 + 121)).isEmpty)
    }
}

@Suite struct Deletes {
    private let credentials = CloudinaryCredentials(apiKey: "123", apiSecret: "abc", cloudName: "djasqoair")
    private func body(_ json: String) -> Data { Data(json.utf8) }

    private func form(_ request: URLRequest) -> [String: String] {
        let text = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        return Dictionary(uniqueKeysWithValues: text.split(separator: "&").map {
            let pair = $0.split(separator: "=", maxSplits: 1).map(String.init)
            return (pair[0], pair[1].removingPercentEncoding ?? pair[1])
        })
    }

    @Test(arguments: [MediaKind.image, .video])
    func destroysWithTheResourceTypeAndPurgesTheCache(kind: MediaKind) {
        let request = Uploader.deleteRequest(credentials: credentials, publicID: "d/k3f9x2ab", kind: kind,
                                             timestamp: Date(timeIntervalSince1970: 1_790_750_686))
        #expect(request.url?.absoluteString == "https://api.cloudinary.com/v1_1/djasqoair/\(kind.rawValue)/destroy")
        #expect(request.httpMethod == "POST")
        let params = form(request)
        #expect(params["public_id"] == "d/k3f9x2ab")
        #expect(params["invalidate"] == "true")
        #expect(params["api_key"] == "123")
        #expect(params["signature"] == uploadSignature(
            ["invalidate": "true", "public_id": "d/k3f9x2ab", "timestamp": "1790750686"], secret: "abc"))
    }

    @Test func olderPublicIDsAreEncodedButSignedAsIs() throws {
        let id = "clouddrop/260929_101500_Screen Shot & co+é"
        let request = Uploader.deleteRequest(credentials: credentials, publicID: id, kind: .image, timestamp: Date(timeIntervalSince1970: 1))
        let text = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(!text.contains(" ") && !text.contains("+") && !text.contains("é"))
        let params = form(request)
        #expect(params["public_id"] == id)
        #expect(params["signature"] == uploadSignature(["invalidate": "true", "public_id": id, "timestamp": "1"], secret: "abc"))
    }

    @Test func okAndNotFoundBothMeanGone() throws {
        #expect(try Uploader.deleteOutcome(status: 200, data: body(#"{"result":"ok"}"#)) == .deleted)
        #expect(try Uploader.deleteOutcome(status: 200, data: body(#"{"result":"not found"}"#)) == .alreadyGone)
    }

    @Test func forbiddenKeepsCloudinaryMessageForTheLog() {
        let raw = #"missing permissions (actions=["destroy"])"#
        #expect(throws: DeleteError.notAllowedToDelete(cloudinaryMessage: raw)) {
            try Uploader.deleteOutcome(status: 403, data: body(#"{"error":{"message":"missing permissions (actions=[\"destroy\"])"}}"#))
        }
        let error: any Error = DeleteError.notAllowedToDelete(cloudinaryMessage: raw)
        #expect(error.localizedDescription.contains("isn't allowed to delete"))
        #expect(String(describing: error).contains(raw))
    }

    @Test func otherFailures() {
        #expect(throws: DeleteError.cloudinary("Cloudinary rejected the API key or secret")) {
            try Uploader.deleteOutcome(status: 401, data: body("{}"))
        }
        #expect(throws: DeleteError.cloudinary("Invalid Signature (HTTP 400)")) {
            try Uploader.deleteOutcome(status: 400, data: body(#"{"error":{"message":"Invalid Signature"}}"#))
        }
        #expect(throws: DeleteError.cloudinary("Cloudinary answered \"error\"")) {
            try Uploader.deleteOutcome(status: 200, data: body(#"{"result":"error"}"#))
        }
        #expect(throws: DeleteError.unexpectedResponse(200)) { try Uploader.deleteOutcome(status: 200, data: body("{}")) }
        #expect(throws: DeleteError.unexpectedResponse(502)) { try Uploader.deleteOutcome(status: 502, data: body("<html>")) }
    }
}

@Suite struct HistoryTimeLabels {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Wednesday 30 Sep 2026, 14:30 UTC.
    private let now = Date(timeIntervalSince1970: 1_790_778_600)

    private func label(hoursAgo hours: Double) -> String {
        HistoryTime.label(for: now.addingTimeInterval(-hours * 3600), now: now, calendar: calendar)
    }

    @Test func todayShowsTheTime() {
        #expect(label(hoursAgo: 0.5) == "02:00 PM")
        #expect(label(hoursAgo: 14) == "12:30 AM")
        #expect(label(hoursAgo: 4.5) == "10:00 AM")
        #expect(label(hoursAgo: 2.5) == "12:00 PM")
    }

    @Test func yesterday() {
        #expect(label(hoursAgo: 15) == "Yesterday")
    }

    @Test func thisWeekShowsTheDay() {
        #expect(label(hoursAgo: 48) == "Mon")
        #expect(label(hoursAgo: 24 * 6) == "Thu")
    }

    @Test func olderShowsTheDate() {
        #expect(label(hoursAgo: 24 * 8) == "22 Sep")
        #expect(label(hoursAgo: 24 * 365) == "30 Sep 2025")
    }

    @Test func tooltipShowsDateAndTime() {
        #expect(HistoryTime.full(now, calendar: calendar) == "30 Sep 2026 at 02:30 PM")
    }

    @Test func clockIsTwelveHour() {
        #expect(HistoryTime.clock(now.addingTimeInterval(9 * 3600), calendar: calendar) == "11:30 PM")
    }
}

@Suite struct CloudinaryThumbnails {
    @Test func cropsOnCloudinaryAsJPEG() {
        #expect(Thumbnail.url(cloudName: "djasqoair", publicID: "d/k3f9x2ab", side: 44).absoluteString
            == "https://res.cloudinary.com/djasqoair/image/upload/c_fill,w_44,h_44/d/k3f9x2ab.jpg")
    }

    @Test func decodesImageDataOnly() throws {
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        let image = try #require(context.makeImage())
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        #expect(Thumbnail.decode(data as Data)?.width == 4)
        #expect(Thumbnail.decode(Data("<html>".utf8)) == nil)
    }
}
