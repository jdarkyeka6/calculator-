import XCTest
import CryptoKit
@testable import Calculator

final class VaultFileCodecTests: XCTestCase {
    func testLargeFileRoundTrip() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("original.bin")
        let cipher = folder.appendingPathComponent("cipher.cvf")
        let restored = folder.appendingPathComponent("restored.bin")

        var bytes = Data(repeating: 0xA5, count: 2_200_123)
        bytes[0] = 0x12
        bytes[1_048_577] = 0x34
        bytes[2_200_122] = 0x56
        try bytes.write(to: source)
        let key = SymmetricKey(size: .bits256)

        let result = try VaultFileCodec.seal(source: source, destination: cipher, key: key)
        XCTAssertEqual(result.byteCount, Int64(bytes.count))
        try VaultFileCodec.open(source: cipher, destination: restored, key: key,
                                expectedBytes: result.byteCount, expectedSHA256: result.sha256)
        XCTAssertEqual(try Data(contentsOf: restored), bytes)
    }

    func testTamperingIsRejected() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("original.bin")
        let cipher = folder.appendingPathComponent("cipher.cvf")
        let output = folder.appendingPathComponent("output.bin")
        try Data(repeating: 7, count: 5000).write(to: source)
        let key = SymmetricKey(size: .bits256)
        let result = try VaultFileCodec.seal(source: source, destination: cipher, key: key)

        var bytes = try Data(contentsOf: cipher)
        bytes[20] ^= 0xFF
        try bytes.write(to: cipher)

        XCTAssertThrowsError(try VaultFileCodec.open(
            source: cipher, destination: output, key: key,
            expectedBytes: result.byteCount, expectedSHA256: result.sha256))
    }

    func testWrongKeyIsRejected() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("original.bin")
        let cipher = folder.appendingPathComponent("cipher.cvf")
        let output = folder.appendingPathComponent("output.bin")
        try Data("private note".utf8).write(to: source)
        let result = try VaultFileCodec.seal(source: source, destination: cipher,
                                             key: SymmetricKey(size: .bits256))

        XCTAssertThrowsError(try VaultFileCodec.open(
            source: cipher, destination: output, key: SymmetricKey(size: .bits256),
            expectedBytes: result.byteCount, expectedSHA256: result.sha256))
    }

    func testTruncatedCiphertextIsRejected() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("original.bin")
        let cipher = folder.appendingPathComponent("cipher.cvf")
        let output = folder.appendingPathComponent("output.bin")
        try Data(repeating: 0x33, count: 8192).write(to: source)
        let key = SymmetricKey(size: .bits256)
        let result = try VaultFileCodec.seal(source: source, destination: cipher, key: key)
        var bytes = try Data(contentsOf: cipher)
        bytes.removeLast(20)
        try bytes.write(to: cipher)

        XCTAssertThrowsError(try VaultFileCodec.open(
            source: cipher, destination: output, key: key,
            expectedBytes: result.byteCount, expectedSHA256: result.sha256))
    }

    private func makeFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
