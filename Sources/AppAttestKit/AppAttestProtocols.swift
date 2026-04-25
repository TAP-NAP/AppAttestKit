//
//  AppAttestProtocols.swift
//  AppAttestDemo
//

import Foundation

/// High-level App Attest API used by application code.
public nonisolated protocol AppAttestClient: Sendable {
    /// Creates and registers a new App Attest key for `credentialName`.
    ///
    /// `credentialName` is caller-defined. AppAttestKit only uses it to find
    /// and reuse the keyId stored for that credential name.
    func prepare(credentialName: String) async throws -> AppAttestCredential

    /// Returns an existing credential or creates one if no local credential exists.
    func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential

    /// Generates an assertion envelope for a caller-selected protected request.
    func generateAssertion(
        credentialName: String,
        request: AppAttestProtectedRequest
    ) async throws -> AppAttestAssertionEnvelope

    /// Returns local status, optionally refined by the configured backend.
    func status(credentialName: String) async throws -> AppAttestCredentialStatus

    /// Deletes local credential metadata for `credentialName`.
    func reset(credentialName: String) async throws
}

/// Server boundary for all App Attest communication.
public nonisolated protocol AppAttestBackend: Sendable {
    func requestChallenge(_ request: AppAttestChallengeRequest) async throws -> AppAttestChallenge
    func registerAttestation(_ request: AppAttestRegistrationRequest) async throws -> AppAttestRegistrationResult
    func credentialStatus(_ request: AppAttestCredentialStatusRequest) async throws -> AppAttestServerCredentialStatus
    func recordAssertionResult(_ record: AppAttestAssertionRecord) async
}

public nonisolated extension AppAttestBackend {
    func credentialStatus(_ request: AppAttestCredentialStatusRequest) async throws -> AppAttestServerCredentialStatus {
        .unknown
    }

    func recordAssertionResult(_ record: AppAttestAssertionRecord) async {}
}

/// Local storage for App Attest key metadata.
public nonisolated protocol AppAttestCredentialStore: Sendable {
    func credential(named credentialName: String) async throws -> AppAttestCredential?
    func save(_ credential: AppAttestCredential) async throws
    func delete(credentialName: String) async throws
}

/// Thin wrapper over Apple's DCAppAttestService, kept injectable for tests.
public nonisolated protocol AppAttestDeviceService: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}
