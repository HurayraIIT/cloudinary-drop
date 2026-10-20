import Foundation
import ImageIO
import Synchronization
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

    /// Rounding to the nearest tenth would print the limit itself: "is 10 MB, image limit is 10 MB".
    @Test(arguments: [
        (MediaKind.image, Int64(10_485_761), "x is 10.1 MB, image limit is 10 MB"),
        (MediaKind.image, Int64(10_537_000), "x is 10.1 MB, image limit is 10 MB"),
        (MediaKind.image, Int64(10_590_000), "x is 10.1 MB, image limit is 10 MB"),
        (MediaKind.image, Int64(10_700_000), "x is 10.2 MB, image limit is 10 MB"),
        (MediaKind.video, Int64(104_857_601), "x is 100.1 MB, video limit is 100 MB"),
    ])
    func justOverTheLimitNeverReadsAsTheLimit(kind: MediaKind, byteCount: Int64, expected: String) {
        #expect(Refusal.tooLarge(filename: "x", kind: kind, byteCount: byteCount).message == expected)
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

@Suite struct CompressionRules {
    @Test func settingFollowsFFmpegThenTheToggle() {
        #expect(CompressionSetting(isFFmpegInstalled: false, isEnabled: true, quality: .crf24) == .noFFmpeg)
        #expect(CompressionSetting(isFFmpegInstalled: true, isEnabled: false, quality: .crf24) == .off)
        #expect(CompressionSetting(isFFmpegInstalled: true, isEnabled: true, quality: .crf24) == .on(.crf24))
        #expect(QualityLevel.default == .crf22)
    }

    @Test func qualityLevelTitles() {
        #expect(QualityLevel.allCases.map(\.menuTitle) == ["CRF 22 · Best quality", "CRF 24", "CRF 26 · Smallest files"])
    }

    @Test func aVideoThatWillBeCompressedIsCheckedAfterwards() {
        #expect(checkMediaFile(filename: "rec.mov", type: .quickTimeMovie, byteCount: 240_000_000, compressingVideos: true)
            == .success(.video))
        // Images are never compressed, so theirs is still checked up front.
        #expect(checkMediaFile(filename: "raw.png", type: .png, byteCount: 14_680_064, compressingVideos: true)
            == .failure(.tooLarge(filename: "raw.png", kind: .image, byteCount: 14_680_064)))
        #expect(checkMediaFile(filename: "rec.mov", type: .quickTimeMovie, byteCount: nil, compressingVideos: true)
            == .failure(.unreadable(filename: "rec.mov")))
    }

    @Test func sizeRefusalsSayHowCompressionCouldHelp() {
        let video = Refusal.tooLarge(filename: "rec.mov", kind: .video, byteCount: 262_144_000)
        #expect(video.message(compression: .noFFmpeg) == "rec.mov is 250 MB, video limit is 100 MB. Install ffmpeg to compress it.")
        #expect(video.message(compression: .off) == "rec.mov is 250 MB, video limit is 100 MB. Turn on Compress Videos to fit it.")
        #expect(video.message(compression: .on(.crf22)) == video.message)
        let image = Refusal.tooLarge(filename: "raw.png", kind: .image, byteCount: 14_680_064)
        #expect(image.message(compression: .off) == image.message)
        #expect(Refusal.notMedia(filename: "a.pdf").message(compression: .off) == "a.pdf isn't an image or video")
    }

    @Test func stillTooLargeSuggestsTheSmallestLevel() {
        #expect(Refusal.stillTooLarge(filename: "rec.mov", byteCount: 125_829_120, quality: .crf22).message
            == "rec.mov is still 120 MB compressed, video limit is 100 MB. Try CRF 26.")
        #expect(Refusal.stillTooLarge(filename: "rec.mov", byteCount: 125_829_120, quality: .crf26).message
            == "rec.mov is still 120 MB compressed, video limit is 100 MB")
        #expect(TemporaryFiles.mentioningCaptureSaved(Refusal.stillTooLarge(filename: "rec.mov", byteCount: 125_829_120, quality: .crf22).message)
            == "rec.mov is still 120 MB compressed, video limit is 100 MB. Try CRF 26. Saved to Downloads.")
    }

    @Test func failureMessages() {
        #expect(Compression.uploadedUncompressedMessage(filename: "rec.mov") == "Couldn't compress rec.mov, uploaded it as is")
        #expect(addingSentence(Compression.failedHint, to: Refusal.tooLarge(filename: "rec.mov", kind: .video, byteCount: 262_144_000).message)
            == "rec.mov is 250 MB, video limit is 100 MB. Couldn't compress it.")
    }

    @Test(arguments: [("rec.mov", "rec.mp4"), ("rec.mp4", "rec.mp4"), ("a.b.MOV", "a.b.mp4"), ("noext", "noext.mp4")])
    func compressedVideosAreNamedLikeTheirShareLink(_ filename: String, _ expected: String) {
        #expect(Compression.compressedFilename(filename) == expected)
    }

    @Test func downloadsNamesTellTheVersionsApart() {
        #expect(Compression.downloadsName("Screen Recording.mov", compressed: false) == "Screen Recording (original).mov")
        #expect(Compression.downloadsName("Screen Recording.mov", compressed: true) == "Screen Recording (compressed).mp4")
        #expect(Compression.downloadsName("noext", compressed: false) == "noext (original)")
    }

    @Test func argumentsUseTheChosenLevelAndTheFixedPipeline() {
        let arguments = Compression.arguments(input: URL(fileURLWithPath: "/in/rec.mov"), output: URL(fileURLWithPath: "/out/x.mp4"),
                                              quality: .crf24)
        let joined = arguments.joined(separator: " ")
        #expect(joined.contains("-i /in/rec.mov"))
        #expect(arguments.last == "/out/x.mp4")
        #expect(joined.contains("-crf 24"))
        for expected in ["-noautorotate", "-hwaccel videotoolbox", "-c:v libx264", "-preset veryfast", "-threads 2",
                         "-fpsmax 30", "-c:a aac -b:a 96k", "-movflags +faststart", "-progress pipe:1"] {
            #expect(joined.contains(expected), "missing \(expected)")
        }
        #expect(joined.contains("scale_vt=w='trunc(iw*min(1\\,1920/max(iw\\,ih))/2)*2':h='trunc(ih*min(1\\,1920/max(iw\\,ih))/2)*2'"))
    }

    @Test func progressReadsSplitChunks() throws {
        var progress = try #require(CompressionProgress(duration: 10))
        #expect(progress.read("frame=10\nout_time_us=2500") == nil)
        #expect(progress.read("000\nspeed=4x\n") == 0.25)
        #expect(progress.read("out_time_us=N/A\nout_time_us=9000000\nout_time_us=12000000\n") == 1)
        #expect(CompressionProgress(duration: nil) == nil)
        #expect(CompressionProgress(duration: 0) == nil)
    }
}

/// Runs the real ffmpeg, so only on a Mac that has it.
@Suite(.enabled(if: Compression.isFFmpegInstalled()), .serialized) struct CompressingWithFFmpeg {
    private func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("clouddrop-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A test pattern of an odd size, so the result shows it was rounded down to even.
    private func makeVideo(in directory: URL, seconds: Int, size: String = "777x1035") async throws -> URL {
        let video = directory.appendingPathComponent("source.mov")
        try await Compressor.run(Compression.ffmpegURL, [
            "-nostdin", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=\(size):rate=60", "-t", "\(seconds)",
            "-c:v", "libx264", "-preset", "ultrafast", video.path,
        ]) { _ in }
        return video
    }

    @Test func compressesToAnEvenSizedMP4() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await makeVideo(in: directory, seconds: 2)
        let output = directory.appendingPathComponent("out.mp4")
        let reported = Recorded<Double>()

        try await Compressor.compress(source, to: output, quality: .crf26) { reported.add($0) }

        #expect(await Compressor.duration(of: output).map { abs($0 - 2) < 0.1 } == true)
        let probe = Recorded<Data>()
        try await Compressor.run(Compression.ffprobeURL, [
            "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_name,width,height,avg_frame_rate",
            "-of", "csv=p=0", output.path,
        ]) { probe.add($0) }
        let description = String(decoding: probe.all.reduce(Data(), +), as: UTF8.self)
        #expect(description.trimmingCharacters(in: .whitespacesAndNewlines) == "h264,776,1034,30/1")
        #expect(reported.all.last.map { $0 > 0.9 } == true)
    }

    @Test func aFileThatIsntAVideoFails() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("fake.mov")
        try Data("not a video".utf8).write(to: source)

        await #expect(throws: CompressionError.self) {
            try await Compressor.compress(source, to: directory.appendingPathComponent("out.mp4"), quality: .crf22) { _ in }
        }
    }

    @Test func cancellingStopsFFmpeg() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try await makeVideo(in: directory, seconds: 15, size: "2880x1800")
        let started = Date()
        let task = Task {
            try await Compressor.compress(source, to: directory.appendingPathComponent("out.mp4"), quality: .crf22) { _ in }
        }
        try await Task.sleep(for: .milliseconds(500))
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Date().timeIntervalSince(started) < 5)
    }
}

/// Collects what a pipe's background queue reports.
private final class Recorded<Value: Sendable>: Sendable {
    private let values = Mutex<[Value]>([])
    var all: [Value] { values.withLock { $0 } }
    func add(_ value: Value) { values.withLock { $0.append(value) } }
}

@Suite struct TemporaryFileCleanup {
    /// A scratch folder standing in for $TMPDIR, with a Downloads folder inside it.
    private func scratch() throws -> (directory: URL, downloads: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("clouddrop-tests-\(UUID().uuidString)")
        let downloads = directory.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        return (directory, downloads)
    }

    private func write(_ text: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    @Test func removesOnlyCloudDropLeftovers() throws {
        let fileManager = FileManager.default
        let (directory, downloads) = try scratch()
        defer { try? fileManager.removeItem(at: directory) }

        let body = TemporaryFiles.multipartBody(in: directory)
        let received = TemporaryFiles.dropFolder(in: directory).appendingPathComponent("shot.png")
        let compressed = TemporaryFiles.compressedVideo(in: directory)
        let kept = ["Downloads", "other.multipart", "clouddrop-notes.txt"]
        for file in [body, received, compressed] + kept.dropFirst().map(directory.appendingPathComponent) {
            try write("x", to: file)
        }

        #expect(TemporaryFiles.removeLeftovers(in: directory, downloads: downloads) == 0)

        #expect(try fileManager.contentsOfDirectory(atPath: directory.path).sorted() == kept.sorted())
        // A file received from a file promise isn't a Capture: its original still exists, so it isn't saved.
        #expect(try fileManager.contentsOfDirectory(atPath: downloads.path).isEmpty)
    }

    @Test func leftoverCapturesAreSavedToDownloads() throws {
        let fileManager = FileManager.default
        let (directory, downloads) = try scratch()
        defer { try? fileManager.removeItem(at: directory) }

        try write("1", to: TemporaryFiles.captureFolder(in: directory).appendingPathComponent("Screen Recording.mov"))
        try write("2", to: TemporaryFiles.captureFolder(in: directory).appendingPathComponent("Screenshot.png"))

        #expect(TemporaryFiles.removeLeftovers(in: directory, downloads: downloads) == 2)

        #expect(try fileManager.contentsOfDirectory(atPath: downloads.path).sorted() == ["cd-Screen Recording.mov", "cd-Screenshot.png"])
        #expect(!fileManager.fileExists(atPath: directory.appendingPathComponent("clouddrop-captures").path))
    }

    @Test func savesCaptureWithPrefixAndRemovesItsFolder() throws {
        let fileManager = FileManager.default
        let (directory, downloads) = try scratch()
        defer { try? fileManager.removeItem(at: directory) }
        let folder = TemporaryFiles.captureFolder(in: directory)
        let file = folder.appendingPathComponent("recording.mov")
        try write("bytes", to: file)

        let saved = TemporaryFiles.saveToDownloads(file, in: downloads)

        #expect(saved == downloads.appendingPathComponent("cd-recording.mov"))
        #expect(fileManager.fileExists(atPath: downloads.appendingPathComponent("cd-recording.mov").path))
        #expect(!fileManager.fileExists(atPath: folder.path))
        #expect(fileManager.fileExists(atPath: folder.deletingLastPathComponent().path))
    }

    @Test func savesCaptureStraightFromTemporaryItems() throws {
        let fileManager = FileManager.default
        let (directory, downloads) = try scratch()
        defer { try? fileManager.removeItem(at: directory) }
        let name = "Screen Recording 2026-10-06 at 11.48.33\u{202f}PM.mov"
        let folder = directory.appendingPathComponent("TemporaryItems/NSIRD_screencaptureui_test")
        let file = folder.appendingPathComponent(name)
        try write("bytes", to: file)

        #expect(TemporaryFiles.saveToDownloads(file, in: downloads) == downloads.appendingPathComponent("cd-\(name)"))
        #expect(!fileManager.fileExists(atPath: file.path))
        // Only CloudDrop's own folders are ever removed.
        #expect(fileManager.fileExists(atPath: folder.path))
    }

    @Test func doesNotDoubleThePrefix() throws {
        let (directory, downloads) = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = TemporaryFiles.captureFolder(in: directory).appendingPathComponent("cd-already.mov")
        try write("bytes", to: file)

        #expect(TemporaryFiles.saveToDownloads(file, in: downloads) == downloads.appendingPathComponent("cd-already.mov"))
    }

    @Test(arguments: [
        ("video.mov", ["cd-video.mov", "cd-video 2.mov"], "cd-video 3.mov"),
        ("recording", ["cd-recording"], "cd-recording 2"),
    ])
    func neverOverwritesInDownloads(name: String, existing: [String], expected: String) throws {
        let (directory, downloads) = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        for taken in existing { try write("old", to: downloads.appendingPathComponent(taken)) }
        let file = TemporaryFiles.captureFolder(in: directory).appendingPathComponent(name)
        try write("new", to: file)

        #expect(TemporaryFiles.saveToDownloads(file, in: downloads) == downloads.appendingPathComponent(expected))
        for taken in existing {
            #expect(try String(contentsOf: downloads.appendingPathComponent(taken), encoding: .utf8) == "old")
        }
    }

    @Test func missingCaptureIsNotSaved() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent-\(UUID().uuidString).mov")
        #expect(TemporaryFiles.saveToDownloads(file) == nil)
    }

    @Test func removeDeletesTheFileAndItsEmptyFolderOnly() throws {
        let fileManager = FileManager.default
        let (directory, _) = try scratch()
        defer { try? fileManager.removeItem(at: directory) }
        let folder = TemporaryFiles.dropFolder(in: directory)
        let first = folder.appendingPathComponent("a.png")
        let second = folder.appendingPathComponent("b.png")
        try write("a", to: first)
        try write("b", to: second)

        TemporaryFiles.remove(first)
        #expect(fileManager.fileExists(atPath: second.path))

        TemporaryFiles.remove(second)
        #expect(!fileManager.fileExists(atPath: folder.path))
        #expect(fileManager.fileExists(atPath: folder.deletingLastPathComponent().path))

        // A user's file never takes its folder with it.
        let userFolder = directory.appendingPathComponent("Projects")
        let userFile = userFolder.appendingPathComponent("c.png")
        try write("c", to: userFile)
        TemporaryFiles.remove(userFile)
        #expect(fileManager.fileExists(atPath: userFolder.path))
    }

    @Test(arguments: [
        "/var/folders/0m/qq3s5b2s5q130r3yh5q5vxdm0000gn/T/TemporaryItems/NSIRD_screencaptureui_0Cpjmt/Screen Recording 2026-10-06 at 11.48.33\u{202f}PM.mov",
        TemporaryFiles.captureFolder().appendingPathComponent("Screenshot.png").path,
    ])
    func capturesAreRecognised(path: String) {
        #expect(TemporaryFiles.isCapture(URL(fileURLWithPath: path)))
    }

    /// Files the user dragged from Finder are theirs, even in a temporary-looking folder, and so are files received
    /// from a file promise.
    @Test(arguments: [
        "/private/var/folders/0m/recording.mov",
        "/tmp/sample.png",
        "/private/tmp/sample.png",
        NSTemporaryDirectory() + "test.mov",
        "/tmp/clouddrop-captures-notes/test.mov",
        TemporaryFiles.dropFolder().appendingPathComponent("file.mov").path,
        "/Users/hurayra/Desktop/my_movie.mov",
        "/Users/hurayra/Downloads/VID_20260918_130730.mp4",
        "/Volumes/External/video.mov",
    ])
    func otherFilesAreNotCaptures(path: String) {
        #expect(!TemporaryFiles.isCapture(URL(fileURLWithPath: path)))
    }

    @Test(arguments: [
        ("rec.mov is 150 MB, video limit is 100 MB", "rec.mov is 150 MB, video limit is 100 MB. Saved to Downloads."),
        ("rec.mov: This API key isn't allowed to upload. Use a key with upload access.",
         "rec.mov: This API key isn't allowed to upload. Use a key with upload access. Saved to Downloads."),
    ])
    func lastErrorSaysTheCaptureWasSaved(message: String, expected: String) {
        #expect(TemporaryFiles.mentioningCaptureSaved(message) == expected)
    }

    @Test func capturesSavedMessage() {
        #expect(TemporaryFiles.capturesSavedMessage(count: 1) == "Saved 1 unfinished Capture to Downloads")
        #expect(TemporaryFiles.capturesSavedMessage(count: 3) == "Saved 3 unfinished Captures to Downloads")
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
        (666_508_855, "636 MB"),
        (1_047_527_424, "999 MB"),
        (1_048_576_000, "1.0 GB"),
        (1_395_864_371, "1.3 GB"),
        (26_843_545_600, "25.0 GB"),
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

@Suite struct UsageLine {
    private let credentials = CloudinaryCredentials(apiKey: "123", apiSecret: "abc", cloudName: "djasqoair")

    @Test func showsCountsStorageAndCredits() {
        let usage = Usage(storedBytes: 666_508_855, creditsUsedPercent: 12.16, images: 1210, videos: 26)
        #expect(usage.line == "1,210 images · 26 videos · 636 MB · 12% of credits")
    }

    @Test func isHiddenUntilEverythingIsKnown() {
        #expect(Usage().line == nil)
        #expect(Usage(storedBytes: 1, creditsUsedPercent: 1, images: 1).line == nil)
        #expect(Usage(images: 1, videos: 1).line == nil)
    }

    @Test(arguments: [(0.0, "0%"), (0.3, "<1%"), (0.5, "1%"), (12.16, "12%"), (99.6, "100%")])
    func creditsAreAWholePercent(_ value: Double, _ label: String) {
        #expect(Usage.percent(value) == label)
    }

    @Test func singularCounts() {
        #expect(Usage(storedBytes: 2048, creditsUsedPercent: 0, images: 1, videos: 0).line == "1 image · 0 videos · 2 KB · 0% of credits")
    }

    @Test func readsTheUsageAPI() throws {
        let request = UsageReader.storageRequest(credentials: credentials)
        #expect(request.url?.absoluteString == "https://api.cloudinary.com/v1_1/djasqoair/usage")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic MTIzOmFiYw==")
        let json = #"{"plan":"Free","storage":{"usage":666508855,"credits_usage":0.62},"credits":{"usage":3.04,"limit":25.0,"used_percent":12.16}}"#
        let usage = try UsageReader.storage(status: 200, data: Data(json.utf8), rateLimitReset: nil)
        #expect(usage == Usage(storedBytes: 666_508_855, creditsUsedPercent: 12.16))
        #expect(throws: HistoryFetchError.unexpectedResponse(200)) {
            try UsageReader.storage(status: 200, data: Data(#"{"storage":{"usage":1}}"#.utf8), rateLimitReset: nil)
        }
    }

    @Test(arguments: [MediaKind.image, .video])
    func countsTheWholeAccountWithoutListing(_ kind: MediaKind) throws {
        let request = UsageReader.countRequest(credentials: credentials, kind: kind)
        #expect(request.url?.absoluteString == "https://api.cloudinary.com/v1_1/djasqoair/resources/search")
        #expect(request.httpMethod == "POST")
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["expression"] as? String == "resource_type:\(kind.rawValue)")
        #expect(body["max_results"] as? Int == 0)
        #expect(try UsageReader.count(status: 200, data: Data(#"{"total_count":26,"resources":[]}"#.utf8), rateLimitReset: nil) == 26)
    }

    @Test func scheduleWaitsForItsIntervalAndRetriesNoSoonerThan30Seconds() {
        let start = Date(timeIntervalSince1970: 1000)
        var schedule = UsageSchedule(interval: 300)
        #expect(schedule.isDue(at: start))
        schedule.lastTry = start
        schedule.isFetching = true
        #expect(!schedule.isDue(at: start.addingTimeInterval(60)))
        schedule.isFetching = false
        // A failure: tried, no answer.
        #expect(!schedule.isDue(at: start.addingTimeInterval(29)))
        #expect(schedule.isDue(at: start.addingTimeInterval(30)))
        schedule.lastAnswer = start
        #expect(!schedule.isDue(at: start.addingTimeInterval(299)))
        #expect(schedule.isDue(at: start.addingTimeInterval(300)))
    }

    @Test func countsAreDueAgainUntilAnAnswerStartsAfterSearchCaughtUp() {
        let upload = Date(timeIntervalSince1970: 1000)
        var schedule = UsageSchedule(interval: 300)
        schedule.lastTry = upload.addingTimeInterval(3)
        schedule.lastAnswer = upload.addingTimeInterval(3)
        #expect(!schedule.isDue(at: upload.addingTimeInterval(20), changedAt: upload))
        #expect(schedule.isDue(at: upload.addingTimeInterval(33), changedAt: upload))
        schedule.lastTry = upload.addingTimeInterval(33)
        schedule.lastAnswer = upload.addingTimeInterval(33)
        #expect(!schedule.isDue(at: upload.addingTimeInterval(100), changedAt: upload))
    }

    @Test func failuresMatchTheLinkHistorys() {
        let reset = "Wed, 30 Sep 2026 07:00:00 GMT"
        #expect(throws: HistoryFetchError.rateLimited(until: HistorySearch.httpDate(reset))) {
            try UsageReader.count(status: 420, data: Data(), rateLimitReset: reset)
        }
        #expect(throws: HistoryFetchError.notAllowedToList(cloudinaryMessage: "nope")) {
            try UsageReader.storage(status: 403, data: Data(#"{"error":{"message":"nope"}}"#.utf8), rateLimitReset: nil)
        }
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
