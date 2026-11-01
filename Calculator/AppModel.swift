import Foundation
import SwiftUI
import LocalAuthentication
import CryptoKit

@MainActor
final class AppModel: ObservableObject {
    enum Route: Equatable { case setup, calculator, biometric, pattern, vault, decoy }

    @Published var route: Route
    @Published var errorMessage: String?
    @Published var lockoutMessage: String?
    @Published var imported = 0
    @Published var skipped = 0
    @Published var importFailed = 0
    @Published var isImporting = false
    @Published var importStatus: String?
    let store = VaultStore()

    private var pendingKey: SymmetricKey?

    init() {
        route = CredentialStore.isConfigured ? .calculator : .setup
    }

    func configure(calculator: String, pattern: String) throws {
        let context = LAContext()
        var issue: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &issue),
              context.biometryType == .faceID else { throw VaultError.unavailableBiometrics }
        guard (6...12).contains(calculator.count), calculator.allSatisfy(\.isNumber),
              pattern.count >= 4 else { throw VaultError.invalidSetup }

        try VaultKeychain.createIfMissing()
        try CredentialStore.configure(calculator: calculator, pattern: pattern)
        route = .calculator
    }

    func calculatorEntered(_ digits: String) -> Bool {
        errorMessage = nil
        guard AttemptLog.secondsRemaining == 0 else {
            errorMessage = "Locked for another \(AttemptLog.secondsRemaining) seconds."
            return false
        }
        if CredentialStore.matchesCalculator(digits) {
            route = .biometric
            return true
        }
        // A normal calculator calculation is not treated as an intrusion.
        if digits.count == CredentialStore.calculatorLength {
            AttemptLog.failure(stage: "Calculator")
            errorMessage = "Incorrect security code."
        }
        return false
    }

    func authenticateWithFaceID() async {
        guard route == .biometric else { return }
        errorMessage = nil
        let context = LAContext()
        context.localizedFallbackTitle = ""
        var issue: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &issue),
              context.biometryType == .faceID else {
            errorMessage = "Face ID is unavailable or temporarily locked. The device passcode cannot open this vault."
            AttemptLog.failure(stage: "Face ID")
            return
        }
        do {
            let accepted = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Verify your identity before the pattern lock."
            )
            guard accepted else { throw VaultError.locked }
            pendingKey = try VaultKeychain.read(using: context)
            route = .pattern
        } catch {
            AttemptLog.failure(stage: "Face ID")
            errorMessage = "Face ID failed: \(error.localizedDescription). No passcode fallback is permitted."
        }
    }

    func patternEntered(_ value: String) {
        guard route == .pattern else { return }
        errorMessage = nil
        guard AttemptLog.secondsRemaining == 0 else {
            errorMessage = "Locked for another \(AttemptLog.secondsRemaining) seconds."
            return
        }
        if CredentialStore.matchesDuress(value) {
            pendingKey = nil
            store.lock()
            route = .decoy
            return
        }
        guard CredentialStore.matchesPattern(value), let key = pendingKey else {
            AttemptLog.failure(stage: "Pattern")
            errorMessage = "Incorrect pattern."
            return
        }
        do {
            try store.unlock(key: key)
            pendingKey = nil
            route = .vault
            AttemptLog.success()
        } catch {
            pendingKey = nil
            route = .calculator
            errorMessage = "Could not open encrypted vault: \(error.localizedDescription)"
        }
    }

    func enableDuressPattern(_ value: String) throws {
        guard route == .vault else { throw VaultError.locked }
        guard !CredentialStore.matchesPattern(value) else {
            throw NSError(domain: "CipherVault", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Duress pattern must be different from your real pattern."
            ])
        }
        try CredentialStore.configureDuress(pattern: value)
    }

    func importFiles(_ urls: [URL], sourceName: String = "Files") async {
        guard route == .vault, !isImporting else { return }
        isImporting = true
        imported = 0
        skipped = 0
        importFailed = 0
        importStatus = "Preparing import…"
        defer {
            isImporting = false
            if route == .vault {
                importStatus = "Import complete: \\(imported) added, \\(skipped) duplicates, \\(importFailed) failed."
            }
            // Intentionally stay unlocked while the app is active.
            // Backgrounding, face-down and the Lock button still secure the vault.
        }

        for source in urls {
            guard route == .vault else { break }
            do {
                if ZIPPhotoImporter.isZIP(source) {
                    let batch = try await ZIPPhotoImporter.extractPhotos(from: source)
                    defer { batch.cleanup() }
                    for (index, photo) in batch.photos.enumerated() {
                        guard route == .vault else { break }
                        importStatus = "ZIP photos: \\(index + 1) of \\(batch.photos.count)"
                        do {
                            let added = try await store.importFile(photo.url, kind: .photo,
                                             name: photo.name, sourceName: "ZIP: " + source.lastPathComponent)
                            if added { imported += 1 } else { skipped += 1 }
                        } catch {
                            importFailed += 1
                            errorMessage = "Could not import \\(photo.name): \\(error.localizedDescription)"
                        }
                    }
                } else {
                    importStatus = "Importing \\(source.lastPathComponent)…"
                    let added = try await store.importFile(source, sourceName: sourceName)
                    if added { imported += 1 } else { skipped += 1 }
                }
            } catch {
                if route != .vault { break }
                importFailed += 1
                errorMessage = "Import failed for \\(source.lastPathComponent): \\(error.localizedDescription)"
            }
        }
    }

    func emergencyCover() {
        pendingKey = nil
        store.lock()
        route = CredentialStore.isConfigured ? .calculator : .setup
    }
}
