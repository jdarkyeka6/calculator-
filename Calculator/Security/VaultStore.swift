import Foundation
import CryptoKit
import UniformTypeIdentifiers

@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var items: [VaultItem] = []
    @Published private(set) var isBusy = false
    @Published var message: String?

    private var vaultKey: SymmetricKey?
    private var lockGeneration: UInt64 = 0
    private let fm = FileManager.default

    private var root: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CipherVault", isDirectory: true)
    }
    private var filesURL: URL { root.appendingPathComponent("encrypted", isDirectory: true) }
    private var manifestURL: URL { root.appendingPathComponent("manifest.cv") }
    private var tempURL: URL {
        fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CipherVaultPreview", isDirectory: true)
    }
    private func encryptedURL(_ id: UUID) -> URL {
        filesURL.appendingPathComponent(id.uuidString).appendingPathExtension("cvf")
    }

    init() { clearTemporaryFiles() }

    func unlock(key: SymmetricKey) throws {
        try ensureDirectories()
        if fm.fileExists(atPath: manifestURL.path) {
            let encrypted = try Data(contentsOf: manifestURL)
            let box = try AES.GCM.SealedBox(combined: encrypted)
            let decoded = try JSONDecoder().decode(VaultIndex.self, from: AES.GCM.open(box, using: key))
            guard decoded.version == 1 else { throw VaultError.corrupted }
            items = decoded.items
        } else {
            items = []
        }
        vaultKey = key
        message = nil
    }

    func lock() {
        lockGeneration &+= 1
        vaultKey = nil
        items = []
        message = nil
        clearTemporaryFiles()
    }

    func importFile(_ source: URL, kind override: VaultKind? = nil,
                    name overrideName: String? = nil, sourceName: String = "Files") async throws -> Bool {
        guard let key = vaultKey else { throw VaultError.locked }
        isBusy = true
        defer { isBusy = false }
        try ensureDirectories()

        let startedGeneration = lockGeneration
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let values = try? source.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey,
                                                           .contentTypeKey, .fileSizeKey])
        let id = UUID()
        let staging = filesURL.appendingPathComponent(id.uuidString + ".partial")
        defer { try? fm.removeItem(at: staging) }

        let details = try await Task.detached(priority: .userInitiated) {
            try VaultFileCodec.seal(source: source, destination: staging, key: key)
        }.value
        // Ignore a completed import if backgrounding, face-down or manual lock happened meanwhile.
        guard lockGeneration == startedGeneration, vaultKey != nil else { throw VaultError.locked }

        if items.contains(where: { $0.sha256 == details.sha256 && $0.byteCount == details.byteCount }) {
            message = "Duplicate skipped: \(overrideName ?? source.lastPathComponent)"
            return false
        }

        let filename = overrideName ?? source.lastPathComponent
        let identifier = values?.contentType?.identifier ??
            UTType(filenameExtension: source.pathExtension)?.identifier ?? UTType.data.identifier
        let kind = override ?? {
            if let type = UTType(identifier) {
                if type.conforms(to: .image) { return .photo }
                if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
            }
            return .file
        }()
        let record = VaultItem(
            id: id, name: filename, kind: kind,
            sha256: details.sha256, byteCount: details.byteCount, importedAt: Date(),
            originalCreatedAt: values?.creationDate, originalModifiedAt: values?.contentModificationDate,
            source: sourceName, contentType: identifier
        )

        let finalURL = encryptedURL(id)
        try fm.moveItem(at: staging, to: finalURL)
        do {
            let newItems = items + [record]
            try persist(newItems, using: key)
            items = newItems
        } catch {
            try? fm.removeItem(at: finalURL)
            throw error
        }
        message = "Imported securely: \(filename)"
        return true
    }

    func createNote(title: String, content: String) async throws {
        guard vaultKey != nil else { throw VaultError.locked }
        try ensureDirectories()
        let source = tempURL.appendingPathComponent(UUID().uuidString + ".txt")
        try Data(content.utf8).write(to: source, options: [.atomic, .completeFileProtection])
        defer { try? fm.removeItem(at: source) }
        _ = try await importFile(source, kind: .note,
                                 name: title.isEmpty ? "Untitled note" : title, sourceName: "Notes")
    }

    func plaintext(for item: VaultItem, maximumBytes: Int64 = 50_000_000) throws -> Data {
        guard vaultKey != nil else { throw VaultError.locked }
        guard item.byteCount <= maximumBytes else { throw VaultError.sizeLimit }
        let url = try decryptToProtectedTemporaryFile(item)
        defer { try? fm.removeItem(at: url) }
        return try Data(contentsOf: url)
    }

    func decryptToProtectedTemporaryFile(_ item: VaultItem) throws -> URL {
        guard let key = vaultKey else { throw VaultError.locked }
        try ensureDirectories()
        let encrypted = encryptedURL(item.id)
        guard fm.fileExists(atPath: encrypted.path) else { throw VaultError.missingFile }
        let ext = UTType(item.contentType)?.preferredFilenameExtension ?? URL(fileURLWithPath: item.name).pathExtension
        let out = tempURL.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext.isEmpty ? "bin" : ext)
        do {
            try VaultFileCodec.open(source: encrypted, destination: out,
                                    key: key, expectedBytes: item.byteCount, expectedSHA256: item.sha256)
        } catch {
            try? fm.removeItem(at: out)
            throw error
        }
        return out
    }

    func preparePreview(for item: VaultItem) async throws -> URL {
        guard let key = vaultKey else { throw VaultError.locked }
        try ensureDirectories()
        let startedGeneration = lockGeneration
        let encrypted = encryptedURL(item.id)
        guard fm.fileExists(atPath: encrypted.path) else { throw VaultError.missingFile }
        let ext = UTType(item.contentType)?.preferredFilenameExtension ??
            URL(fileURLWithPath: item.name).pathExtension
        let out = tempURL.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext.isEmpty ? "bin" : ext)
        do {
            try await Task.detached(priority: .userInitiated) {
                try VaultFileCodec.open(source: encrypted, destination: out, key: key,
                                        expectedBytes: item.byteCount, expectedSHA256: item.sha256)
            }.value
            guard startedGeneration == lockGeneration, vaultKey != nil else {
                try? fm.removeItem(at: out)
                throw VaultError.locked
            }
            return out
        } catch {
            try? fm.removeItem(at: out)
            throw error
        }
    }

    func removeTemporaryFile(_ url: URL) { try? fm.removeItem(at: url) }

    func delete(_ item: VaultItem) throws {
        guard let key = vaultKey else { throw VaultError.locked }
        let remainder = items.filter { $0.id != item.id }
        try persist(remainder, using: key)
        items = remainder
        try? fm.removeItem(at: encryptedURL(item.id))
    }

    private func persist(_ records: [VaultItem], using key: SymmetricKey) throws {
        let data = try JSONEncoder().encode(VaultIndex(items: records))
        guard let combined = try AES.GCM.seal(data, using: key).combined else { throw VaultError.corrupted }
        try combined.write(to: manifestURL, options: [.atomic, .completeFileProtection])
    }

    private func ensureDirectories() throws {
        for dir in [root, filesURL, tempURL] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try (dir as NSURL).setResourceValue(FileProtectionType.complete, forKey: .fileProtectionKey)
        }
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var directory = root
        try directory.setResourceValues(excluded)
        var previewDirectory = tempURL
        try previewDirectory.setResourceValues(excluded)
    }

    private func clearTemporaryFiles() {
        try? fm.removeItem(at: tempURL)
    }
}
