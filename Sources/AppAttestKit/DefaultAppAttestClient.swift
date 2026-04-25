//
//  DefaultAppAttestClient.swift
//  AppAttestDemo
//

import CryptoKit
import Foundation

/// Default implementation of the reusable App Attest client.
public actor DefaultAppAttestClient: AppAttestClient {
    private let backend: AppAttestBackend
    private let credentialStore: AppAttestCredentialStore
    private let deviceService: AppAttestDeviceService
    private let environment: AppAttestEnvironment
    #if DEBUG
    private let progressHandler: (@MainActor @Sendable (String) async -> Void)?
    #endif

    #if DEBUG
    public init(
        backend: AppAttestBackend,
        credentialStore: AppAttestCredentialStore = KeychainAppAttestCredentialStore(),
        deviceService: AppAttestDeviceService = DCAppAttestDeviceService(),
        environment: AppAttestEnvironment = .production,
        progressHandler: (@MainActor @Sendable (String) async -> Void)? = nil
    ) {
        self.backend = backend
        self.credentialStore = credentialStore
        self.deviceService = deviceService
        self.environment = environment
        self.progressHandler = progressHandler
    }
    #else
    public init(
        backend: AppAttestBackend,
        credentialStore: AppAttestCredentialStore = KeychainAppAttestCredentialStore(),
        deviceService: AppAttestDeviceService = DCAppAttestDeviceService(),
        environment: AppAttestEnvironment = .production
    ) {
        self.backend = backend
        self.credentialStore = credentialStore
        self.deviceService = deviceService
        self.environment = environment
    }
    #endif

    public func prepare(credentialName: String) async throws -> AppAttestCredential {
        let credentialName = try Self.normalizedCredentialName(credentialName)
        await reportProgress("check DCAppAttestService.isSupported")
        guard deviceService.isSupported else {
            throw AppAttestError.unsupportedDevice
        }

        await reportProgress("backend.requestChallenge(purpose: attestation)")
        let challenge = try await backend.requestChallenge(
            AppAttestChallengeRequest(purpose: .attestation, credentialName: credentialName)
        )
        try Self.validateChallenge(challenge, purpose: .attestation)
        await reportProgress("DCAppAttestService.generateKey")
        let keyId = try await deviceService.generateKey()
        await reportProgress("SHA256(challenge)")
        let clientDataHash = Data(SHA256.hash(data: challenge.challenge))
        await reportProgress("DCAppAttestService.attestKey")
        let attestationObject = try await deviceService.attestKey(keyId, clientDataHash: clientDataHash)

        await reportProgress("backend.registerAttestation")
        let result = try await backend.registerAttestation(
            AppAttestRegistrationRequest(
                credentialName: credentialName,
                keyId: keyId,
                challengeId: challenge.challengeId,
                attestationObject: attestationObject
            )
        )

        guard result.status == .accepted else {
            throw AppAttestError.attestationRejected("Backend registration returned \(result.status.rawValue).")
        }

        await reportProgress("credentialStore.save")
        let now = Date()
        let credential = AppAttestCredential(
            credentialName: credentialName,
            keyId: keyId,
            credentialId: result.credentialId,
            status: .ready,
            environment: environment,
            createdAt: now,
            updatedAt: now
        )

        try await credentialStore.save(credential)
        return credential
    }

    public func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential {
        let credentialName = try Self.normalizedCredentialName(credentialName)
        await reportProgress("credentialStore.credential")
        if let credential = try await credentialStore.credential(named: credentialName),
           credential.status == .ready {
            await reportProgress("reuse saved keyId")
            return credential
        }

        await reportProgress("no ready credential, run prepare")
        return try await prepare(credentialName: credentialName)
    }

    public func generateAssertion(
        credentialName: String,
        request: AppAttestProtectedRequest
    ) async throws -> AppAttestAssertionEnvelope {
        let credentialName = try Self.normalizedCredentialName(credentialName)
        await reportProgress("check DCAppAttestService.isSupported")
        guard deviceService.isSupported else {
            throw AppAttestError.unsupportedDevice
        }

        await reportProgress("credentialStore.credential")
        guard let credential = try await credentialStore.credential(named: credentialName) else {
            throw AppAttestError.credentialMissing(credentialName)
        }

        guard credential.status == .ready else {
            throw AppAttestError.invalidConfiguration(
                "No ready App Attest credential exists for \(credentialName). Run prepareIfNeeded first."
            )
        }

        await reportProgress("backend.requestChallenge(purpose: assertion)")
        let challenge = try await backend.requestChallenge(
            AppAttestChallengeRequest(purpose: .assertion, credentialName: credentialName)
        )
        try Self.validateChallenge(challenge, purpose: .assertion)
        await reportProgress("build request binding")
        let binding = request.binding(challenge: challenge.challenge)
        await reportProgress("DCAppAttestService.generateAssertion")
        let assertionObject = try await deviceService.generateAssertion(
            credential.keyId,
            clientDataHash: try binding.clientDataHash()
        )

        let envelope = AppAttestAssertionEnvelope(
            credentialName: credentialName,
            keyId: credential.keyId,
            challengeId: challenge.challengeId,
            assertionObject: assertionObject,
            requestBinding: binding
        )

        await reportProgress("backend.recordAssertionResult")
        await backend.recordAssertionResult(
            AppAttestAssertionRecord(
                credentialName: credentialName,
                keyId: credential.keyId,
                challengeId: challenge.challengeId,
                assertionObject: assertionObject,
                requestBinding: binding,
                createdAt: Date()
            )
        )

        return envelope
    }

    public func status(credentialName: String) async throws -> AppAttestCredentialStatus {
        let credentialName = try Self.normalizedCredentialName(credentialName)
        await reportProgress("credentialStore.credential")
        guard let credential = try await credentialStore.credential(named: credentialName) else {
            return .notPrepared
        }

        await reportProgress("backend.credentialStatus")
        let serverStatus = try await backend.credentialStatus(
            AppAttestCredentialStatusRequest(credentialName: credentialName, keyId: credential.keyId)
        )

        switch serverStatus {
        case .accepted:
            return .ready
        case .revoked:
            let revokedCredential = AppAttestCredential(
                credentialName: credential.credentialName,
                keyId: credential.keyId,
                credentialId: credential.credentialId,
                status: .revoked,
                environment: credential.environment,
                createdAt: credential.createdAt,
                updatedAt: Date()
            )
            try await credentialStore.save(revokedCredential)
            return .revoked
        case .unknown:
            return credential.status
        }
    }

    public func reset(credentialName: String) async throws {
        let credentialName = try Self.normalizedCredentialName(credentialName)
        await reportProgress("credentialStore.delete")
        try await credentialStore.delete(credentialName: credentialName)
    }

    private static func normalizedCredentialName(_ credentialName: String) throws -> String {
        let trimmed = credentialName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppAttestError.invalidConfiguration("credentialName cannot be empty.")
        }
        return trimmed
    }

    private static func validateChallenge(_ challenge: AppAttestChallenge, purpose: AppAttestPurpose) throws {
        guard let expiresAt = challenge.expiresAt else {
            return
        }

        guard expiresAt > Date() else {
            throw AppAttestError.challengeRejected(
                "\(purpose.rawValue) challenge \(challenge.challengeId) expired at \(expiresAt)."
            )
        }
    }

    private func reportProgress(_ message: String) async {
        #if DEBUG
        await progressHandler?(message)
        #endif
    }
}
