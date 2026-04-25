//
//  AppAttestKitTests.swift
//  AppAttestDemoTests
//

import Foundation
import Testing
@testable import AppAttestKit

struct AppAttestKitTests {
    @Test func prepareStoresCredentialOnlyAfterBackendAccepts() async throws {
        let store = InMemoryCredentialStore()
        let backend = MockAppAttestBackend()
        let deviceService = MockAppAttestDeviceService()
        let client = DefaultAppAttestClient(
            backend: backend,
            credentialStore: store,
            deviceService: deviceService,
            environment: .development
        )

        let credential = try await client.prepare(credentialName: "installation_keyid")
        let stored = try await store.credential(named: "installation_keyid")

        #expect(credential.credentialName == "installation_keyid")
        #expect(stored?.keyId == "mock-key-id")
        #expect(await backend.challengeRequests.map(\.purpose) == [.attestation])
        #expect(await backend.registrationRequests.count == 1)
        #expect(deviceService.didGenerateKey)
        #expect(deviceService.attestedKeyId == "mock-key-id")
    }

    @Test func prepareIfNeededReusesExistingCredential() async throws {
        let now = Date()
        let existing = AppAttestCredential(
            credentialName: "primary_credential",
            keyId: "existing-key",
            credentialId: "server-existing-key",
            status: .ready,
            environment: .production,
            createdAt: now,
            updatedAt: now
        )
        let store = InMemoryCredentialStore()
        try await store.save(existing)

        let backend = MockAppAttestBackend()
        let client = DefaultAppAttestClient(
            backend: backend,
            credentialStore: store,
            deviceService: MockAppAttestDeviceService(),
            environment: .production
        )

        let credential = try await client.prepareIfNeeded(credentialName: "primary_credential")

        #expect(credential.keyId == "existing-key")
        #expect(await backend.challengeRequests.isEmpty)
    }

    @Test func resetOnlyDeletesSelectedCredentialName() async throws {
        let now = Date()
        let store = InMemoryCredentialStore()
        try await store.save(
            AppAttestCredential(
                credentialName: "installation_keyid",
                keyId: "install-key",
                credentialId: nil,
                status: .ready,
                environment: .development,
                createdAt: now,
                updatedAt: now
            )
        )
        try await store.save(
            AppAttestCredential(
                credentialName: "secondary_credential",
                keyId: "secondary-key",
                credentialId: nil,
                status: .ready,
                environment: .development,
                createdAt: now,
                updatedAt: now
            )
        )

        let client = DefaultAppAttestClient(
            backend: MockAppAttestBackend(),
            credentialStore: store,
            deviceService: MockAppAttestDeviceService(),
            environment: .development
        )

        try await client.reset(credentialName: "installation_keyid")

        #expect(try await store.credential(named: "installation_keyid") == nil)
        #expect(try await store.credential(named: "secondary_credential")?.keyId == "secondary-key")
    }

    @Test func assertionUsesBackendChallengeAndCredentialNameHeader() async throws {
        let store = InMemoryCredentialStore()
        let now = Date()
        try await store.save(
            AppAttestCredential(
                credentialName: "primary_credential",
                keyId: "stored-key",
                credentialId: nil,
                status: .ready,
                environment: .development,
                createdAt: now,
                updatedAt: now
            )
        )

        let backend = MockAppAttestBackend()
        let deviceService = MockAppAttestDeviceService()
        let client = DefaultAppAttestClient(
            backend: backend,
            credentialStore: store,
            deviceService: deviceService,
            environment: .development
        )

        let envelope = try await client.generateAssertion(
            credentialName: "primary_credential",
            request: AppAttestProtectedRequest(
                method: "POST",
                path: "/api/protected",
                body: Data("one".utf8)
            )
        )

        var urlRequest = URLRequest(url: URL(string: "https://example.com/api/protected")!)
        try envelope.applyHeaders(to: &urlRequest)

        #expect(envelope.keyId == "stored-key")
        #expect(urlRequest.value(forHTTPHeaderField: "X-App-Attest-Credential-Name") == "primary_credential")
        #expect(await backend.challengeRequests.map(\.purpose) == [.assertion])
        #expect(await backend.assertionRecords.count == 1)
        #expect(deviceService.assertedKeyId == "stored-key")
    }

    @Test func generateAssertionFailsWithoutPreparedCredential() async throws {
        let client = DefaultAppAttestClient(
            backend: MockAppAttestBackend(),
            credentialStore: InMemoryCredentialStore(),
            deviceService: MockAppAttestDeviceService(),
            environment: .development
        )

        do {
            _ = try await client.generateAssertion(
                credentialName: "missing",
                request: AppAttestProtectedRequest(method: "GET", path: "/protected")
            )
            Issue.record("Expected missing credential error.")
        } catch AppAttestError.credentialMissing(let credentialName) {
            #expect(credentialName == "missing")
        }
    }

    @Test func requestBindingChangesWhenBodyChanges() throws {
        let challenge = Data("challenge".utf8)
        let first = AppAttestProtectedRequest(
            method: "POST",
            path: "/api/protected",
            body: Data("one".utf8)
        ).binding(challenge: challenge)
        let second = AppAttestProtectedRequest(
            method: "POST",
            path: "/api/protected",
            body: Data("two".utf8)
        ).binding(challenge: challenge)

        #expect(try first.clientDataHash() != second.clientDataHash())
    }

    @Test func httpBackendDetectsForbiddenLocalHosts() {
        #expect(HTTPAppAttestBackend.isForbiddenReleaseHost(URL(string: "http://localhost:8080")!))
        #expect(HTTPAppAttestBackend.isForbiddenReleaseHost(URL(string: "http://127.0.0.1:8080")!))
        #expect(HTTPAppAttestBackend.isForbiddenReleaseHost(URL(string: "http://127.0.0.2:8080")!))
        #expect(HTTPAppAttestBackend.isForbiddenReleaseHost(URL(string: "http://127.1.2.3")!))
        #expect(HTTPAppAttestBackend.isForbiddenReleaseHost(URL(string: "http://[::1]:8080")!))
        #expect(HTTPAppAttestBackend.isForbiddenReleaseHost(URL(string: "http://printer.local")!))
        #expect(!HTTPAppAttestBackend.isForbiddenReleaseHost(URL(string: "https://api.example.com")!))
    }

    @Test func generateAssertionFailsForRevokedCredential() async throws {
        let now = Date()
        let store = InMemoryCredentialStore()
        try await store.save(
            AppAttestCredential(
                credentialName: "revoked_credential",
                keyId: "revoked-key",
                credentialId: nil,
                status: .revoked,
                environment: .development,
                createdAt: now,
                updatedAt: now
            )
        )

        let client = DefaultAppAttestClient(
            backend: MockAppAttestBackend(),
            credentialStore: store,
            deviceService: MockAppAttestDeviceService(),
            environment: .development
        )

        do {
            _ = try await client.generateAssertion(
                credentialName: "revoked_credential",
                request: AppAttestProtectedRequest(method: "GET", path: "/protected")
            )
            Issue.record("Expected credentialMissing error for revoked credential.")
        } catch AppAttestError.credentialMissing(let name) {
            #expect(name == "revoked_credential")
        }
    }

    @Test func prepareRejectsExpiredChallenge() async throws {
        let store = InMemoryCredentialStore()
        let backend = ExpiredChallengeBackend()
        let client = DefaultAppAttestClient(
            backend: backend,
            credentialStore: store,
            deviceService: MockAppAttestDeviceService(),
            environment: .development
        )

        do {
            _ = try await client.prepare(credentialName: "installation_keyid")
            Issue.record("Expected challengeRejected error for expired challenge.")
        } catch AppAttestError.challengeRejected {
            // expected
        }
    }

    #if DEBUG
    @Test func localDebugBackendUsesFixedChallengeAndExportsGeneratedObjects() async throws {
        let backend = LocalDebugAppAttestBackend()
        let challenge = try await backend.requestChallenge(
            AppAttestChallengeRequest(purpose: .attestation, credentialName: "installation_keyid")
        )

        #expect(challenge.challengeId == "nearbycommunity")
        #expect(String(data: challenge.challenge, encoding: .utf8) == "nearbycommunity")
        #expect(challenge.expiresAt == nil)

        _ = try await backend.registerAttestation(
            AppAttestRegistrationRequest(
                credentialName: "installation_keyid",
                keyId: "debug-key",
                challengeId: challenge.challengeId,
                attestationObject: Data("attestation".utf8)
            )
        )
        await backend.recordAssertionResult(
            AppAttestAssertionRecord(
                credentialName: "installation_keyid",
                keyId: "debug-key",
                challengeId: challenge.challengeId,
                assertionObject: Data("assertion".utf8),
                requestBinding: AppAttestProtectedRequest(
                    method: "GET",
                    path: "/debug"
                ).binding(challenge: challenge.challenge),
                createdAt: Date()
            )
        )

        let json = try await backend.exportDebugJSONString()

        #expect(json.contains("attestationObject"))
        #expect(json.contains("assertionObject"))
        #expect(json.contains("debug-key"))
        #expect(json.contains("credentialName"))
        #expect(try await backend.latestAttestationObject() == Data("attestation".utf8))
    }
    #endif
}

private actor InMemoryCredentialStore: AppAttestCredentialStore {
    private var credentials: [String: AppAttestCredential] = [:]

    func credential(named credentialName: String) async throws -> AppAttestCredential? {
        credentials[credentialName]
    }

    func save(_ credential: AppAttestCredential) async throws {
        credentials[credential.credentialName] = credential
    }

    func delete(credentialName: String) async throws {
        credentials.removeValue(forKey: credentialName)
    }
}

private actor MockAppAttestBackend: AppAttestBackend {
    private(set) var challengeRequests: [AppAttestChallengeRequest] = []
    private(set) var registrationRequests: [AppAttestRegistrationRequest] = []
    private(set) var assertionRecords: [AppAttestAssertionRecord] = []

    func requestChallenge(_ request: AppAttestChallengeRequest) async throws -> AppAttestChallenge {
        challengeRequests.append(request)
        return AppAttestChallenge(
            challengeId: "challenge-\(challengeRequests.count)",
            challenge: Data("challenge-\(challengeRequests.count)".utf8),
            expiresAt: Date().addingTimeInterval(300)
        )
    }

    func registerAttestation(_ request: AppAttestRegistrationRequest) async throws -> AppAttestRegistrationResult {
        registrationRequests.append(request)
        return AppAttestRegistrationResult(
            credentialId: "server-\(request.keyId)",
            status: .accepted
        )
    }

    func credentialStatus(_ request: AppAttestCredentialStatusRequest) async throws -> AppAttestServerCredentialStatus {
        .unknown
    }

    func recordAssertionResult(_ record: AppAttestAssertionRecord) async {
        assertionRecords.append(record)
    }
}

private final class MockAppAttestDeviceService: AppAttestDeviceService, @unchecked Sendable {
    var isSupported = true
    private(set) var didGenerateKey = false
    private(set) var attestedKeyId: String?
    private(set) var assertedKeyId: String?

    func generateKey() async throws -> String {
        didGenerateKey = true
        return "mock-key-id"
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        attestedKeyId = keyId
        return Data("mock-attestation".utf8)
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        assertedKeyId = keyId
        return Data("mock-assertion".utf8)
    }
}

private actor ExpiredChallengeBackend: AppAttestBackend {
    /// Negative offset so the challenge is already expired when the client receives it.
    private static let expiredChallengeOffsetSeconds: TimeInterval = -60

    func requestChallenge(_ request: AppAttestChallengeRequest) async throws -> AppAttestChallenge {
        AppAttestChallenge(
            challengeId: "expired-id",
            challenge: Data("expired".utf8),
            expiresAt: Date().addingTimeInterval(Self.expiredChallengeOffsetSeconds)
        )
    }

    func registerAttestation(_ request: AppAttestRegistrationRequest) async throws -> AppAttestRegistrationResult {
        AppAttestRegistrationResult(credentialId: nil, status: .accepted)
    }
}
