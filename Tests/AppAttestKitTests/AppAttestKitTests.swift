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

    @Test func prepareIfNeededCoalescesConcurrentCallsForSameCredentialName() async throws {
        let store = InMemoryCredentialStore()
        let backend = MockAppAttestBackend(challengeDelayNanos: 50_000_000)
        let deviceService = MockAppAttestDeviceService()
        let client = DefaultAppAttestClient(
            backend: backend,
            credentialStore: store,
            deviceService: deviceService,
            environment: .development
        )

        async let first = client.prepareIfNeeded(credentialName: "installation_keyid")
        async let second = client.prepareIfNeeded(credentialName: "installation_keyid")
        let credentials = try await [first, second]

        #expect(credentials[0].keyId == credentials[1].keyId)
        #expect(await backend.challengeRequests.map(\.purpose) == [.attestation])
        #expect(await backend.registrationRequests.count == 1)
        #expect(deviceService.generateKeyCount == 1)
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

    @Test func generateAssertionFailsForRevokedCredential() async throws {
        let store = InMemoryCredentialStore()
        let now = Date()
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

        let backend = MockAppAttestBackend()
        let deviceService = MockAppAttestDeviceService()
        let client = DefaultAppAttestClient(
            backend: backend,
            credentialStore: store,
            deviceService: deviceService,
            environment: .development
        )

        do {
            _ = try await client.generateAssertion(
                credentialName: "revoked_credential",
                request: AppAttestProtectedRequest(method: "POST", path: "/api/protected")
            )
            Issue.record("Expected revoked credential to fail before assertion.")
        } catch AppAttestError.credentialNotReady(let credentialName) {
            #expect(credentialName == "revoked_credential")
        }

        #expect(await backend.challengeRequests.isEmpty)
        #expect(deviceService.assertedKeyId == nil)
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

    @Test func statusPersistsRevokedCredentialState() async throws {
        let store = InMemoryCredentialStore()
        let now = Date()
        try await store.save(
            AppAttestCredential(
                credentialName: "primary_credential",
                keyId: "stored-key",
                credentialId: "server-stored-key",
                status: .ready,
                environment: .development,
                createdAt: now,
                updatedAt: now
            )
        )

        let client = DefaultAppAttestClient(
            backend: MockAppAttestBackend(serverCredentialStatus: .revoked),
            credentialStore: store,
            deviceService: MockAppAttestDeviceService(),
            environment: .development
        )

        let status = try await client.status(credentialName: "primary_credential")
        let stored = try await store.credential(named: "primary_credential")

        #expect(status == .revoked)
        #expect(stored?.status == .revoked)
        #expect(stored?.createdAt == now)
        #expect(stored?.updatedAt != now)
    }

    @Test func statusDoesNotOverwriteCredentialReplacedWhileCheckingServer() async throws {
        let store = InMemoryCredentialStore()
        let now = Date()
        try await store.save(
            AppAttestCredential(
                credentialName: "primary_credential",
                keyId: "old-key",
                credentialId: "server-old-key",
                status: .ready,
                environment: .development,
                createdAt: now,
                updatedAt: now
            )
        )

        let replacement = AppAttestCredential(
            credentialName: "primary_credential",
            keyId: "new-key",
            credentialId: "server-new-key",
            status: .ready,
            environment: .development,
            createdAt: now,
            updatedAt: now
        )
        let backend = MockAppAttestBackend(
            serverCredentialStatus: .revoked,
            credentialStatusHook: {
                try await store.save(replacement)
            }
        )
        let client = DefaultAppAttestClient(
            backend: backend,
            credentialStore: store,
            deviceService: MockAppAttestDeviceService(),
            environment: .development
        )

        let status = try await client.status(credentialName: "primary_credential")
        let stored = try await store.credential(named: "primary_credential")

        #expect(status == .ready)
        #expect(stored?.keyId == "new-key")
        #expect(stored?.status == .ready)
    }


    @Test func prepareRejectsExpiredChallenge() async throws {
        let backend = MockAppAttestBackend(challengeExpiresAt: Date().addingTimeInterval(-1))
        let deviceService = MockAppAttestDeviceService()
        let client = DefaultAppAttestClient(
            backend: backend,
            credentialStore: InMemoryCredentialStore(),
            deviceService: deviceService,
            environment: .development
        )

        do {
            _ = try await client.prepare(credentialName: "installation_keyid")
            Issue.record("Expected expired attestation challenge to fail.")
        } catch AppAttestError.challengeRejected(let message) {
            #expect(message.contains("attestation challenge"))
        }

        #expect(!deviceService.didGenerateKey)
        #expect(await backend.registrationRequests.isEmpty)
    }

    @Test func prepareRejectsShortChallenge() async throws {
        let backend = MockAppAttestBackend(challenge: Data("short".utf8))
        let deviceService = MockAppAttestDeviceService()
        let client = DefaultAppAttestClient(
            backend: backend,
            credentialStore: InMemoryCredentialStore(),
            deviceService: deviceService,
            environment: .development
        )

        do {
            _ = try await client.prepare(credentialName: "installation_keyid")
            Issue.record("Expected short attestation challenge to fail.")
        } catch AppAttestError.challengeRejected(let message) {
            #expect(message.contains("too short"))
            #expect(message.contains("5 bytes"))
        }

        #expect(!deviceService.didGenerateKey)
        #expect(await backend.registrationRequests.isEmpty)
    }

    @Test func generateAssertionRejectsExpiredChallenge() async throws {
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

        let backend = MockAppAttestBackend(challengeExpiresAt: Date().addingTimeInterval(-1))
        let deviceService = MockAppAttestDeviceService()
        let client = DefaultAppAttestClient(
            backend: backend,
            credentialStore: store,
            deviceService: deviceService,
            environment: .development
        )

        do {
            _ = try await client.generateAssertion(
                credentialName: "primary_credential",
                request: AppAttestProtectedRequest(method: "POST", path: "/api/protected")
            )
            Issue.record("Expected expired assertion challenge to fail.")
        } catch AppAttestError.challengeRejected(let message) {
            #expect(message.contains("assertion challenge"))
        }

        #expect(await backend.challengeRequests.map(\.purpose) == [.assertion])
        #expect(deviceService.assertedKeyId == nil)
        #expect(await backend.assertionRecords.isEmpty)
    }

    @Test func generateAssertionRejectsShortChallenge() async throws {
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

        let backend = MockAppAttestBackend(challenge: Data("tiny".utf8))
        let deviceService = MockAppAttestDeviceService()
        let client = DefaultAppAttestClient(
            backend: backend,
            credentialStore: store,
            deviceService: deviceService,
            environment: .development
        )

        do {
            _ = try await client.generateAssertion(
                credentialName: "primary_credential",
                request: AppAttestProtectedRequest(method: "POST", path: "/api/protected")
            )
            Issue.record("Expected short assertion challenge to fail.")
        } catch AppAttestError.challengeRejected(let message) {
            #expect(message.contains("too short"))
            #expect(message.contains("4 bytes"))
        }

        #expect(await backend.challengeRequests.map(\.purpose) == [.assertion])
        #expect(deviceService.assertedKeyId == nil)
        #expect(await backend.assertionRecords.isEmpty)
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
        #expect(HTTPAppAttestBackend.isForbiddenReleaseHost(URL(string: "http://127.1.2.3:8080")!))
        #expect(HTTPAppAttestBackend.isForbiddenReleaseHost(URL(string: "http://[::1]:8080")!))
        #expect(HTTPAppAttestBackend.isForbiddenReleaseHost(URL(string: "http://[0:0:0:0:0:0:0:1]:8080")!))
        #expect(HTTPAppAttestBackend.isForbiddenReleaseHost(URL(string: "http://printer.local")!))
        #expect(!HTTPAppAttestBackend.isForbiddenReleaseHost(URL(string: "https://api.example.com")!))
    }

    @Test func httpBackendReleaseGuardRequiresHTTPSAndNonLocalHost() {
        #expect(HTTPAppAttestBackend.isForbiddenReleaseBackend(URL(string: "http://api.example.com")!))
        #expect(HTTPAppAttestBackend.isForbiddenReleaseBackend(URL(string: "https://localhost:8443")!))
        #expect(HTTPAppAttestBackend.isForbiddenReleaseBackend(URL(string: "https://127.1.2.3")!))
        #expect(HTTPAppAttestBackend.isForbiddenReleaseBackend(URL(string: "https://service.local")!))
        #expect(!HTTPAppAttestBackend.isForbiddenReleaseBackend(URL(string: "https://api.example.com")!))
    }


    @Test func httpBackendEndpointJoinsPathsWithoutDoubleEncoding() throws {
        let backend = try HTTPAppAttestBackend(baseURL: URL(string: "https://api.example.com/v1/")!)

        #expect(backend.endpoint("/app-attest/challenges").absoluteString == "https://api.example.com/v1/app-attest/challenges")
        #expect(backend.endpoint("app-attest/challenges").absoluteString == "https://api.example.com/v1/app-attest/challenges")
        #expect(backend.endpoint("/app-attest/%2F/challenges").absoluteString == "https://api.example.com/v1/app-attest/%2F/challenges")
    }

    #if DEBUG
    @Test func localDebugBackendUsesFixedChallengeAndExportsGeneratedObjects() async throws {
        let backend = LocalDebugAppAttestBackend()
        let challenge = try await backend.requestChallenge(
            AppAttestChallengeRequest(purpose: .attestation, credentialName: "installation_keyid")
        )

        #expect(challenge.challengeId == LocalDebugAppAttestBackend.defaultChallengeString)
        #expect(String(data: challenge.challenge, encoding: .utf8) == LocalDebugAppAttestBackend.defaultChallengeString)
        #expect((challenge.expiresAt ?? Date()) > Date().addingTimeInterval(60 * 60))

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
        #expect(try await backend.latestAssertionObject() == Data("assertion".utf8))
        #expect(try await backend.latestAssertionObjectBase64URL() == Data("assertion".utf8).appAttestBase64URL)
        let expectedClientData = try AppAttestProtectedRequest(
            method: "GET",
            path: "/debug"
        ).binding(challenge: challenge.challenge).canonicalData()
        #expect(try await backend.latestAssertionClientData() == expectedClientData)
    }

    @Test func localDebugBackendUsesCustomChallenge() async throws {
        let backend = LocalDebugAppAttestBackend(challengeString: "custom-debug-challenge")
        let challenge = try await backend.requestChallenge(
            AppAttestChallengeRequest(purpose: .assertion, credentialName: "installation_keyid")
        )

        #expect(challenge.challengeId == "custom-debug-challenge")
        #expect(String(data: challenge.challenge, encoding: .utf8) == "custom-debug-challenge")
    }

    @Test func localDebugBackendRejectsAssertionObjectExportBeforeAssertion() async throws {
        let backend = LocalDebugAppAttestBackend()

        do {
            _ = try await backend.latestAssertionObject()
            Issue.record("Expected missing assertionObject export to fail.")
        } catch AppAttestDebugExportError.noAssertionObject {
            return
        }
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
    private let challenge: Data
    private let challengeExpiresAt: Date?
    private let challengeDelayNanos: UInt64
    private let serverCredentialStatus: AppAttestServerCredentialStatus
    private let credentialStatusHook: (@Sendable () async throws -> Void)?

    init(
        challenge: Data = Data("challenge-0000000001".utf8),
        challengeExpiresAt: Date? = Date().addingTimeInterval(300),
        challengeDelayNanos: UInt64 = 0,
        serverCredentialStatus: AppAttestServerCredentialStatus = .unknown,
        credentialStatusHook: (@Sendable () async throws -> Void)? = nil
    ) {
        self.challenge = challenge
        self.challengeExpiresAt = challengeExpiresAt
        self.challengeDelayNanos = challengeDelayNanos
        self.serverCredentialStatus = serverCredentialStatus
        self.credentialStatusHook = credentialStatusHook
    }

    func requestChallenge(_ request: AppAttestChallengeRequest) async throws -> AppAttestChallenge {
        challengeRequests.append(request)
        if challengeDelayNanos > 0 {
            try await Task.sleep(nanoseconds: challengeDelayNanos)
        }
        return AppAttestChallenge(
            challengeId: "challenge-\(challengeRequests.count)",
            challenge: challenge,
            expiresAt: challengeExpiresAt
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
        try await credentialStatusHook?()
        return serverCredentialStatus
    }

    func recordAssertionResult(_ record: AppAttestAssertionRecord) async {
        assertionRecords.append(record)
    }
}

private final class MockAppAttestDeviceService: AppAttestDeviceService, @unchecked Sendable {
    var isSupported = true
    private(set) var didGenerateKey = false
    private(set) var generateKeyCount = 0
    private(set) var attestedKeyId: String?
    private(set) var assertedKeyId: String?

    func generateKey() async throws -> String {
        didGenerateKey = true
        generateKeyCount += 1
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
