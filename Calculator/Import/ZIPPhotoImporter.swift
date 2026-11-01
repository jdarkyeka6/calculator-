import Foundation
import ZIPFoundation

/// Reads only image files from a ZIP. Never uses an archive-provided path on disk.
/// Extracted plaintext is written into a protected temporary directory and
/// removed as soon as the vault has encrypted the batch.
enum ZIPPhotoImporter {
    static let maxEntries = 5_000
    static let maxPhotos = 500
    static let maxPhotoBytes: UInt64 = 50 * 1_024 * 1_024
    static let maxTotalBytes: UInt64 = 1_024 * 1_024 * 1_024

    static let extensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif",
        "webp", "tif", "tiff", "bmp", "avif"
    ]

    struct Photo {
        let url: URL
        let name: String
    }

    struct Batch {
        let directory: URL
        let photos: [Photo]

        func cleanup() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    enum ImportError: LocalizedError {
        case tooManyEntries, tooManyPhotos, tooLarge, noPhotos

        var errorDescription: String? {
            switch self {
            case .tooManyEntries: return "ZIP contains too many entries (limit: 5,000)."
            case .tooManyPhotos: return "ZIP contains more than 500 supported photos."
            case .tooLarge: return "A photo exceeds 50 MB or the ZIP expands past 1 GB."
            case .noPhotos: return "No supported photos were found inside the ZIP."
            }
        }
    }

    static func isZIP(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "zip"
    }

    /// Holding the security scope here allows Files/iCloud file-provider URLs
    /// to be read for the entire extraction, even on the worker thread.
    static func extractPhotos(from source: URL) async throws -> Batch {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        return try await Task.detached(priority: .userInitiated) {
            try extractSynchronously(from: source)
        }.value
    }

    private static func extractSynchronously(from source: URL) throws -> Batch {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory
            .appendingPathComponent("CipherVaultZIP-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.protectionKey: FileProtectionType.complete])
        // The directory must be deleted on every error; on success the caller owns it.
        do {
            let archive = try Archive(url: source, accessMode: .read)
            var photos: [Photo] = []
            var entries = 0
            var totalBytes: UInt64 = 0
            for entry in archive {
                try Task.checkCancellation()
                entries += 1
                guard entries <= maxEntries else { throw ImportError.tooManyEntries }
                guard entry.type == .file else { continue } // Skip links and directories.

                let components = entry.path.split(separator: "/")
                let name = components.last.map(String.init) ?? ""
                // ZIPs made on macOS can contain AppleDouble metadata files.
                guard !name.hasPrefix("."),
                      !components.contains(where: { $0 == "__MACOSX" }) else { continue }
                let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
                guard extensions.contains(ext) else { continue }
                guard photos.count < maxPhotos else { throw ImportError.tooManyPhotos }

                let bytes = UInt64(entry.uncompressedSize)
                guard bytes <= maxPhotoBytes, totalBytes <= maxTotalBytes - bytes else {
                    throw ImportError.tooLarge
                }
                totalBytes += bytes

                // A generated flat path prevents ZIP traversal and file collisions.
                let output = directory.appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(ext)
                guard fm.createFile(atPath: output.path, contents: nil,
                                    attributes: [.protectionKey: FileProtectionType.complete]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let writer = try FileHandle(forWritingTo: output)
                do {
                    try archive.extract(entry, consumer: { chunk in
                        try Task.checkCancellation()
                        try writer.write(contentsOf: chunk)
                    })
                    try writer.close()
                    photos.append(Photo(url: output, name: name))
                } catch {
                    try? writer.close()
                    throw error
                }
            }
            guard !photos.isEmpty else { throw ImportError.noPhotos }
            return Batch(directory: directory, photos: photos)
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
    }
}
