//
//  KeychainAppAttestCredentialStore.swift
//  AppAttestDemo
//

import Foundation
import Security

/// Keychain-backed storage for App Attest credential metadata.
///
/// This stores `credentialName -> keyId` and related metadata. It does not
/// store App Attest private key material; Apple manages that key material.
// SAFETY: The store keeps only immutable configuration. Keychain operations are
// system calls, and callers must not mutate injected encoders/decoders after init.
public nonisolated struct KeychainAppAttestCredentialStore: AppAttestCredentialStore, @unchecked Sendable {
    private let service: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        service: String = Bundle.main.bundleIdentifier.map { "\($0).AppAttestKit.Credentials" } ?? "AppAttestKit.Credentials",
        encoder: JSONEncoder = .appAttestCanonical,
        decoder: JSONDecoder = .appAttestDefault
    ) {
        self.service = service
        self.encoder = encoder
        self.decoder = decoder
    }

    public func credential(named credentialName: String) async throws -> AppAttestCredential? {
        var query = baseQuery(for: credentialName)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw AppAttestError.keychain(status: status)
        }
        guard let data = result as? Data else {
            throw AppAttestError.invalidConfiguration("Keychain returned non-data credential payload.")
        }
        return try decoder.decode(AppAttestCredential.self, from: data)
    }

    public func save(_ credential: AppAttestCredential) async throws {
        let data = try encoder.encode(credential)
        let query = baseQuery(for: credential.credentialName)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AppAttestError.keychain(status: updateStatus)
        }

        var addQuery = query
        addQuery.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AppAttestError.keychain(status: addStatus)
        }
    }

    public func delete(credentialName: String) async throws {
        let status = SecItemDelete(baseQuery(for: credentialName) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppAttestError.keychain(status: status)
        }
    }

    private func baseQuery(for credentialName: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialName
        ]
    }
}
