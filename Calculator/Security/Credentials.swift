import Foundation
import CommonCrypto
import Security

struct CredentialVerifier: Codable {
    let salt: Data
    let hash: Data
}

enum CredentialStore {
    private static let calculatorKey = "cv.credentials.calculator"
    private static let patternKey = "cv.credentials.pattern"
    private static let duressKey = "cv.credentials.duress"
    private static let rounds: UInt32 = 200_000

    static var isConfigured: Bool {
        UserDefaults.standard.data(forKey: calculatorKey) != nil &&
        UserDefaults.standard.data(forKey: patternKey) != nil
    }

    static var calculatorLength: Int {
        UserDefaults.standard.integer(forKey: "cv.credentials.length")
    }

    static func configure(calculator: String, pattern: String) throws {
        guard (6...12).contains(calculator.count),
              calculator.allSatisfy(\.isNumber),
              pattern.count >= 4 else { throw VaultError.invalidSetup }
        let calculatorVerifier = try verifier(for: calculator)
        let patternVerifier = try verifier(for: pattern)
        UserDefaults.standard.set(try JSONEncoder().encode(calculatorVerifier), forKey: calculatorKey)
        UserDefaults.standard.set(try JSONEncoder().encode(patternVerifier), forKey: patternKey)
        UserDefaults.standard.set(calculator.count, forKey: "cv.credentials.length")
    }

    static func configureDuress(pattern: String) throws {
        guard pattern.count >= 4 else { throw VaultError.invalidSetup }
        UserDefaults.standard.set(try JSONEncoder().encode(try verifier(for: pattern)), forKey: duressKey)
    }

    static func matchesCalculator(_ value: String) -> Bool { matches(value, key: calculatorKey) }
    static func matchesPattern(_ value: String) -> Bool { matches(value, key: patternKey) }
    static func matchesDuress(_ value: String) -> Bool { matches(value, key: duressKey) }
    static var hasDuressPattern: Bool { UserDefaults.standard.data(forKey: duressKey) != nil }

    private static func matches(_ value: String, key: String) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode(CredentialVerifier.self, from: data),
              let candidate = try? derive(value, salt: stored.salt),
              stored.hash.count == candidate.count else { return false }
        // Do not use normal Data equality, which may exit on the first different byte.
        var diff: UInt8 = 0
        for i in stored.hash.indices { diff |= stored.hash[i] ^ candidate[i] }
        return diff == 0
    }

    private static func verifier(for value: String) throws -> CredentialVerifier {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw VaultError.corrupted
        }
        let salt = Data(bytes)
        return CredentialVerifier(salt: salt, hash: try derive(value, salt: salt))
    }

    private static func derive(_ value: String, salt: Data) throws -> Data {
        let password = Array(value.utf8CString)
        var result = [UInt8](repeating: 0, count: 32)
        let derivedCount = result.count
        let status = password.withUnsafeBufferPointer { passwordPointer in
            salt.withUnsafeBytes { saltPointer in
                result.withUnsafeMutableBufferPointer { output in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPointer.baseAddress,
                        password.count - 1,
                        saltPointer.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        rounds,
                        output.baseAddress,
                        derivedCount
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw VaultError.corrupted }
        return Data(result)
    }
}

/// Records are device-local operational logs, not tamper-proof forensic evidence.
enum AttemptLog {
    private static let key = "cv.security.events"
    private static let countKey = "cv.security.failed"
    private static let deadlineKey = "cv.security.lockout"

    static var events: [SecurityEvent] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SecurityEvent].self, from: data)) ?? []
    }

    static var secondsRemaining: Int {
        let interval = UserDefaults.standard.double(forKey: deadlineKey) - Date().timeIntervalSince1970
        return max(0, Int(ceil(interval)))
    }

    static func failure(stage: String) {
        add(stage: stage, result: "Denied")
        let count = UserDefaults.standard.integer(forKey: countKey) + 1
        UserDefaults.standard.set(count, forKey: countKey)
        if count >= 5 {
            UserDefaults.standard.set(Date().addingTimeInterval(60).timeIntervalSince1970, forKey: deadlineKey)
            UserDefaults.standard.set(0, forKey: countKey)
        }
    }

    static func success() {
        UserDefaults.standard.set(0, forKey: countKey)
        add(stage: "Vault", result: "Unlocked")
    }

    private static func add(stage: String, result: String) {
        var updated = events
        updated.insert(SecurityEvent(id: UUID(), time: Date(), stage: stage, result: result), at: 0)
        updated = Array(updated.prefix(100))
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
