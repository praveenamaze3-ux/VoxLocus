//
//  EncryptionService.swift
//  VoxLocus
//
//  Created by Praveen V on 30/06/26.
//
// AES-GCM not only encrypts but also ensures it isnt tampered with.
//
//  EncryptionService.swift
//  VoxLocus
//
//  Encrypts note payloads with AES-GCM (CryptoKit) before they touch
//  the network or Firebase. The symmetric key lives only in the device
//  Keychain — it is never uploaded.
//

import CryptoKit
import Security
import Foundation

enum EncryptionService {

    // Updated bundle/tag to match the VoxLocus target.
    private static let keychainKeyTag = "com.voxlocus.encryptionkey"

    // MARK: - Key management

    /// Fetches the persisted symmetric key, generating and storing one on first use.
    static func loadOrCreateKey() -> SymmetricKey {
        if let existing = readKeyFromKeychain() { return existing }
        let newKey = SymmetricKey(size: .bits256)
        saveKeyToKeychain(newKey)
        return newKey
    }

    // MARK: - Encrypt / Decrypt

    /// Encodes `value` as JSON, then seals it with AES-GCM.
    /// Returns a combined Data blob: nonce (12 B) + ciphertext + tag (16 B).
    static func encrypt<T: Encodable>(_ value: T) throws -> Data {
        let plaintext = try JSONEncoder().encode(value)
        let key = loadOrCreateKey()
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.sealingFailed
        }
        return combined
    }

    /// Decrypts a combined AES-GCM blob and decodes it as `T`.
    static func decrypt<T: Decodable>(_ combinedData: Data, as type: T.Type) throws -> T {
        let key = loadOrCreateKey()
        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        let plaintext = try AES.GCM.open(sealedBox, using: key)
        return try JSONDecoder().decode(T.self, from: plaintext)
    }

    // MARK: - Errors

    enum EncryptionError: LocalizedError {
        case sealingFailed
        var errorDescription: String? {
            "AES-GCM sealing failed — could not produce a combined ciphertext blob."
        }
    }

    // MARK: - Keychain helpers

    private static func readKeyFromKeychain() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKeyTag,
            kSecReturnData  as String: true,
            kSecMatchLimit  as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func saveKeyToKeychain(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass           as String: kSecClassGenericPassword,
            kSecAttrAccount     as String: keychainKeyTag,
            kSecValueData       as String: keyData,
            kSecAttrAccessible  as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        // Delete any stale entry before writing the new one.
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}
