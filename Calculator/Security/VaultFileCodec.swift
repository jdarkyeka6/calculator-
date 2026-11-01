import Foundation
import CryptoKit

struct SealedFileResult {
    let sha256: String
    let byteCount: Int64
}

/// Authenticated, individually encrypted 1 MiB chunks.
/// Format: ASCII "CVF1", then for each chunk LE UInt32 sealed length + AES-GCM combined data.
/// Each chunk gets a fresh random nonce. Truncation is detected by original byteCount in manifest.
enum VaultFileCodec {
    static let chunkSize = 1_048_576
    private static let magic = Data("CVF1".utf8)

    static func seal(source: URL, destination: URL, key: SymmetricKey) throws -> SealedFileResult {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        try (destination as NSURL).setResourceValue(FileProtectionType.complete, forKey: .fileProtectionKey)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try output.write(contentsOf: magic)

        var hash = SHA256()
        var total: Int64 = 0
        while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
            hash.update(data: chunk)
            total += Int64(chunk.count)
            guard let combined = try AES.GCM.seal(chunk, using: key).combined else {
                throw VaultError.corrupted
            }
            try writeLength(UInt32(combined.count), to: output)
            try output.write(contentsOf: combined)
        }
        return SealedFileResult(sha256: hash.finalize().map { String(format: "%02x", $0) }.joined(), byteCount: total)
    }

    static func open(source: URL, destination: URL, key: SymmetricKey, expectedBytes: Int64, expectedSHA256: String) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard try input.read(upToCount: 4) == magic else { throw VaultError.corrupted }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        try (destination as NSURL).setResourceValue(FileProtectionType.complete, forKey: .fileProtectionKey)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        var total: Int64 = 0
        var hash = SHA256()
        while let header = try input.read(upToCount: 4), !header.isEmpty {
            guard header.count == 4 else { throw VaultError.corrupted }
            let length = header.enumerated().reduce(UInt32(0)) { acc, part in
                acc | (UInt32(part.element) << (UInt32(part.offset) * 8))
            }
            guard length >= 28, length <= UInt32(chunkSize + 28),
                  let ciphertext = try input.read(upToCount: Int(length)),
                  ciphertext.count == Int(length) else { throw VaultError.corrupted }
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            let clear = try AES.GCM.open(box, using: key)
            hash.update(data: clear)
            total += Int64(clear.count)
            guard total <= expectedBytes else { throw VaultError.corrupted }
            try output.write(contentsOf: clear)
        }
        let actualSHA256 = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard total == expectedBytes, actualSHA256 == expectedSHA256 else { throw VaultError.corrupted }
    }

    private static func writeLength(_ length: UInt32, to output: FileHandle) throws {
        let bytes: [UInt8] = [
            UInt8(truncatingIfNeeded: length),
            UInt8(truncatingIfNeeded: length >> 8),
            UInt8(truncatingIfNeeded: length >> 16),
            UInt8(truncatingIfNeeded: length >> 24)
        ]
        try output.write(contentsOf: Data(bytes))
    }
}
