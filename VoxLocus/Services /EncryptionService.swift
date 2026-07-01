//
//  EncryptionService.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//

import CryptoKit
import Security
import Foundation

enum EncryptionService {

    private static let keychainKeyTag = "com.smartnotes.encryptionkey"

    nonisolated static func loadOrCreateKey() -> SymmetricKey {
        if let existing = readKeyFromKeychain() {
            return existing
        }
        let newKey = SymmetricKey(size: .bits256)
        saveKeyToKeychain(newKey)
        return newKey
    }

    nonisolated static func encrypt<T: Encodable>(_ value: T) throws -> Data {
        let plaintext = try JSONEncoder().encode(value)
        let key = loadOrCreateKey()
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.sealingFailed
        }
        return combined
    }

    nonisolated static func decrypt<T: Decodable>(_ combinedData: Data, as type: T.Type) throws -> T {
        let key = loadOrCreateKey()
        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        let plaintext = try AES.GCM.open(sealedBox, using: key)
        return try JSONDecoder().decode(T.self, from: plaintext)
    }

    enum EncryptionError: LocalizedError {
        case sealingFailed
        var errorDescription: String? { "Failed to seal note payload for encryption." }
    }

    // MARK: - Keychain plumbing

    private static func readKeyFromKeychain() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKeyTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func saveKeyToKeychain(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKeyTag,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}

