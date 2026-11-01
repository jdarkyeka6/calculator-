import Foundation

enum VaultKind: String, Codable, CaseIterable, Identifiable {
    case photo, video, note, file
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .photo: return "photo"
        case .video: return "video"
        case .note: return "note.text"
        case .file: return "doc"
        }
    }
}

struct VaultItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var kind: VaultKind
    let sha256: String
    let byteCount: Int64
    let importedAt: Date
    let originalCreatedAt: Date?
    let originalModifiedAt: Date?
    let source: String
    let contentType: String
}

struct VaultIndex: Codable {
    var version: Int = 1
    var items: [VaultItem] = []
}

enum VaultError: LocalizedError {
    case locked, corrupted, missingFile, sizeLimit, invalidSetup, unavailableBiometrics
    var errorDescription: String? {
        switch self {
        case .locked: return "The vault is locked. Unlock it before continuing."
        case .corrupted: return "Encrypted file data is invalid or cannot be authenticated."
        case .missingFile: return "The requested encrypted file is missing."
        case .sizeLimit: return "This preview is too large to load entirely into memory."
        case .invalidSetup: return "Set a 6–12 digit calculator code and a pattern of at least four dots."
        case .unavailableBiometrics: return "Face ID must be enrolled and available before setup."
        }
    }
}

struct SecurityEvent: Codable, Identifiable {
    let id: UUID
    let time: Date
    let stage: String
    let result: String
}
