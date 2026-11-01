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
        guard route == .vault else { return }
        imported = 0
        skipped = 0
        for url in urls {
            if route != .vault { break }
            do {
                let didAdd = try await store.importFile(url, sourceName: sourceName)
                if didAdd { imported += 1 } else { skipped += 1 }
            } catch {
                errorMessage = "Import failed for \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        // User-selected setting: lock after *every* import batch, even partial failure.
        emergencyCover()
    }

    func emergencyCover() {
        pendingKey = nil
        store.lock()
        route = CredentialStore.isConfigured ? .calculator : .setup
    }
}
