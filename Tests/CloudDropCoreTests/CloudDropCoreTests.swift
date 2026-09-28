import Foundation
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
    @Test func screenRecordingName() {
        #expect(PublicID.slug(fromFilename: "Screen Recording 2026-09-28 at 14.15.03.mov")
            == "screen-recording-2026-09-28-at-14-15-03")
    }

    @Test func nameWithNoUsableCharactersIsEmpty() {
        #expect(PublicID.slug(fromFilename: "ছবি.png") == "")
    }

    @Test func collapsesAndTrimsSeparators() {
        #expect(PublicID.slug(fromFilename: "  --Hello   World!!--.JPG") == "hello-world")
    }

    @Test func capsAtFortyCharactersWithoutTrailingHyphen() {
        let slug = PublicID.slug(fromFilename: String(repeating: "a", count: 39) + " b c d.png")
        #expect(slug.count <= PublicID.maxSlugLength)
        #expect(!slug.hasSuffix("-"))
        #expect(slug == String(repeating: "a", count: 39))
    }

    @Test func fullPublicID() throws {
        let date = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 9, day: 28, hour: 14, minute: 15, second: 3)))
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(PublicID.make(originalFilename: "Screenshot.png", date: date, randomSuffix: "k3f9", timeZone: utc)
            == "clouddrop/260928_141503_k3f9_screenshot")
        #expect(PublicID.make(originalFilename: "ছবি.heic", date: date, randomSuffix: "k3f9", timeZone: utc)
            == "clouddrop/260928_141503_k3f9")
    }

    @Test func randomSuffixIsShortAndSafe() {
        let suffix = PublicID.randomSuffix()
        #expect(suffix.count == 4)
        #expect(suffix.allSatisfy { $0.isLowercase || $0.isNumber })
    }
}

@Suite struct Signing {
    @Test func matchesCloudinaryDocumentationExample() {
        let params = ["eager": "w_400,h_300,c_pad|w_260,h_200,c_crop", "public_id": "sample_image", "timestamp": "1315060510"]
        #expect(uploadSignature(params, secret: "abcd") == "bfd09f95f331f558cbd1320e67aa8d488770583e")
    }

    @Test func signsOurUploadParametersInSortedOrder() {
        let params = ["timestamp": "1790000000", "public_id": "clouddrop/260928_141503_k3f9_shot", "asset_folder": "clouddrop"]
        #expect(uploadSignature(params, secret: "secret123") == "0bdc6dcae76cd7cf0eb01559f56c534c32f07ada")
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
}

@Suite struct ShareLinks {
    @Test func originalsAreUntouched() throws {
        let url = try #require(URL(string: "https://res.cloudinary.com/djasqoair/video/upload/v1/clouddrop/x.mov"))
        #expect(ShareLink.make(secureURL: url) == url)
    }

    @Test(arguments: ["heic", "HEIC", "heif"])
    func heicIsDeliveredAsJPEG(_ ext: String) throws {
        let url = try #require(URL(string: "https://res.cloudinary.com/djasqoair/image/upload/v1/clouddrop/260928_141503_k3f9_img.\(ext)"))
        #expect(ShareLink.make(secureURL: url).absoluteString
            == "https://res.cloudinary.com/djasqoair/image/upload/v1/clouddrop/260928_141503_k3f9_img.jpg")
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
}
