import Foundation
import CryptoKit
import LocalAuthentication
import Security

enum VaultKeychain {
    private static let service = "com.jdarkyeka6.calculator.vaultkey"
    private static let account = "master-v1"

    static func createIfMissing() throws {
        var query = baseQuery()
        query[kSecReturnData as String] = false
        let exists = SecItemCopyMatching(query as CFDictionary, nil)
        if exists == errSecSuccess { return }
        // An auth-required item can return interaction-not-allowed; never overwrite it.
        guard exists == errSecItemNotFound else {
            if exists == errSecInteractionNotAllowed || exists == errSecAuthFailed { return }
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(exists))
        }

        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet, &error
        ) else { throw error!.takeRetainedValue() as Error }

        var keyBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes) == errSecSuccess else {
            throw VaultError.corrupted
        }
        var add = baseQuery()
        add[kSecValueData as String] = Data(keyBytes)
        add[kSecAttrAccessControl as String] = access
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    static func read(using context: LAContext) throws -> SymmetricKey {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        query[kSecUseOperationPrompt as String] = "Unlock your encrypted vault"
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return SymmetricKey(data: data)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
