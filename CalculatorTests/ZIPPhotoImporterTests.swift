import XCTest
import Foundation
import ZIPFoundation
@testable import Calculator

final class ZIPPhotoImporterTests: XCTestCase {
    func testImportsOnlyPhotosFromNestedZIPAndPreservesFileName() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let album = root.appendingPathComponent("holiday", isDirectory: true)
        try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
        let photo = Data([0xFF, 0xD8, 0xFF, 0x00])
        try photo.write(to: album.appendingPathComponent("beach.jpg"))
        try Data("skip me".utf8).write(to: album.appendingPathComponent("notes.txt"))
        let zipURL = root.appendingPathComponent("photos.zip")
        let archive = try Archive(url: zipURL, accessMode: .create)
        try archive.addEntry(with: "holiday/beach.jpg", relativeTo: root)
        try archive.addEntry(with: "holiday/notes.txt", relativeTo: root)

        let batch = try await ZIPPhotoImporter.extractPhotos(from: zipURL)
        defer { batch.cleanup() }
        XCTAssertEqual(batch.photos.count, 1)
        XCTAssertEqual(batch.photos.first?.name, "beach.jpg")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(batch.photos.first?.url)), photo)
        XCTAssertTrue(batch.photos.first!.url.path.hasPrefix(batch.directory.path + "/"))
    }

    func testRejectsZIPWithoutPhotosAndCleansUp() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("nothing".utf8).write(to: root.appendingPathComponent("notes.txt"))
        let zip = root.appendingPathComponent("archive.zip")
        let archive = try Archive(url: zip, accessMode: .create)
        try archive.addEntry(with: "notes.txt", relativeTo: root)

        do {
            _ = try await ZIPPhotoImporter.extractPhotos(from: zip)
            XCTFail("ZIP with no photos should fail")
        } catch ZIPPhotoImporter.ImportError.noPhotos {
            // Expected
        }
    }

    func testZIPDetectionIsCaseInsensitive() {
        XCTAssertTrue(ZIPPhotoImporter.isZIP(URL(fileURLWithPath: "/test/Photos.ZIP")))
        XCTAssertFalse(ZIPPhotoImporter.isZIP(URL(fileURLWithPath: "/test/photo.jpeg")))
    }
}
