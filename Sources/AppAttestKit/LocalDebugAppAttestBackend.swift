//
//  LocalDebugAppAttestBackend.swift
//  AppAttestDemo
//

import Foundation

#if DEBUG
/// DEBUG-only backend that generates deterministic local challenges and exports
/// App Attest objects when no server is available.
///
/// This does not perform production-grade attestation or assertion validation.
public actor LocalDebugAppAttestBackend: AppAttestBackend {
    public static let fixedChallengeString = "nearbycommunity"
    public static let challengeLifetime: TimeInterval = 24 * 60 * 60

    private var challenges: [AppAttestDebugChallengeRecord] = []
    private var registrations: [AppAttestDebugRegistrationRecord] = []
    private var assertions: [AppAttestDebugAssertionRecord] = []

    public init() {}

    public func requestChallenge(_ request: AppAttestChallengeRequest) async throws -> AppAttestChallenge {
        let challenge = Data(Self.fixedChallengeString.utf8)
        let expiresAt = Date().addingTimeInterval(Self.challengeLifetime)
        let record = AppAttestDebugChallengeRecord(
            challengeId: Self.fixedChallengeString,
            challenge: challenge,
            purpose: request.purpose,
            credentialName: request.credentialName,
            expiresAt: expiresAt,
            createdAt: Date()
        )
        challenges.append(record)

        return AppAttestChallenge(
            challengeId: Self.fixedChallengeString,
            challenge: challenge,
            expiresAt: expiresAt
        )
    }

    public func registerAttestation(_ request: AppAttestRegistrationRequest) async throws -> AppAttestRegistrationResult {
        registrations.append(
            AppAttestDebugRegistrationRecord(
                credentialName: request.credentialName,
                keyId: request.keyId,
                challengeId: request.challengeId,
                attestationObject: request.attestationObject,
                createdAt: Date()
            )
        )

        return AppAttestRegistrationResult(
            credentialId: "local-debug-\(request.keyId)",
            status: .accepted
        )
    }

    public func credentialStatus(_ request: AppAttestCredentialStatusRequest) async throws -> AppAttestServerCredentialStatus {
        .accepted
    }

    public func recordAssertionResult(_ record: AppAttestAssertionRecord) async {
        assertions.append(
            AppAttestDebugAssertionRecord(
                credentialName: record.credentialName,
                keyId: record.keyId,
                challengeId: record.challengeId,
                assertionObject: record.assertionObject,
                requestBinding: record.requestBinding,
                createdAt: record.createdAt
            )
        )
    }

    public func exportDebugData() throws -> Data {
        let export = AppAttestDebugExport(
            exportedAt: Date(),
            challenges: challenges,
            registrations: registrations,
            assertions: assertions
        )

        return try JSONEncoder.appAttestPretty.encode(export)
    }

    public func exportDebugJSONString() throws -> String {
        String(data: try exportDebugData(), encoding: .utf8) ?? "{}"
    }

    /// Returns the most recent raw attestation object produced by
    /// `DCAppAttestService.attestKey`.
    public func latestAttestationObject() throws -> Data {
        guard let registration = registrations.last else {
            throw AppAttestDebugExportError.noAttestationObject
        }
        return registration.attestationObject
    }

    /// Returns the most recent raw attestation object as base64url.
    public func latestAttestationObjectBase64URL() throws -> String {
        try latestAttestationObject().appAttestBase64URL
    }

    /// Returns the most recent challenge issued by this local debug backend.
    public func latestChallenge() throws -> AppAttestDebugChallengeRecord {
        guard let challenge = challenges.last else {
            throw AppAttestDebugExportError.noChallenge
        }
        return challenge
    }
}

public nonisolated enum AppAttestDebugExportError: Error, LocalizedError, Sendable {
    case noChallenge
    case noAttestationObject

    public var errorDescription: String? {
        switch self {
        case .noChallenge:
            return "No challenge has been generated yet. Run Prepare Credential first."
        case .noAttestationObject:
            return "No attestationObject has been generated yet. Run attestation first."
        }
    }
}

public nonisolated struct AppAttestDebugExport: Encodable, Hashable, Sendable {
    public let exportedAt: Date
    public let challenges: [AppAttestDebugChallengeRecord]
    public let registrations: [AppAttestDebugRegistrationRecord]
    public let assertions: [AppAttestDebugAssertionRecord]
}

public nonisolated struct AppAttestDebugChallengeRecord: Encodable, Hashable, Sendable {
    public let challengeId: String
    public let challenge: Data
    public let purpose: AppAttestPurpose
    public let credentialName: String
    public let expiresAt: Date?
    public let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case challengeId
        case challenge
        case purpose
        case credentialName
        case expiresAt
        case createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encode(challenge.appAttestBase64URL, forKey: .challenge)
        try container.encode(purpose, forKey: .purpose)
        try container.encode(credentialName, forKey: .credentialName)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

public nonisolated struct AppAttestDebugRegistrationRecord: Encodable, Hashable, Sendable {
    public let credentialName: String
    public let keyId: String
    public let challengeId: String
    public let attestationObject: Data
    public let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case credentialName
        case keyId
        case challengeId
        case attestationObject
        case attestationCertificates
        case attestationCertificateExportError
        case createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(credentialName, forKey: .credentialName)
        try container.encode(keyId, forKey: .keyId)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encode(attestationObject.appAttestBase64URL, forKey: .attestationObject)
        do {
            try container.encode(
                Self.attestationCertificates(from: attestationObject),
                forKey: .attestationCertificates
            )
        } catch {
            try container.encode(error.localizedDescription, forKey: .attestationCertificateExportError)
        }
        try container.encode(createdAt, forKey: .createdAt)
    }

    private static func attestationCertificates(from attestationObject: Data) throws -> [AppAttestDebugCertificate] {
        var decoder = AppAttestCBORDecoder(data: attestationObject)
        guard case .map(let root) = try decoder.decode(),
              case .map(let attestationStatement)? = root[text: "attStmt"],
              case .array(let certificateValues)? = attestationStatement[text: "x5c"] else {
            return []
        }

        return certificateValues.enumerated().compactMap { index, value in
            guard case .bytes(let der) = value else {
                return nil
            }
            return AppAttestDebugCertificate(index: index, der: der)
        }
    }
}

public nonisolated struct AppAttestDebugCertificate: Encodable, Hashable, Sendable {
    public let index: Int
    public let der: Data

    private enum CodingKeys: String, CodingKey {
        case index
        case derBase64
        case derBase64URL
        case pem
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(der.base64EncodedString(), forKey: .derBase64)
        try container.encode(der.appAttestBase64URL, forKey: .derBase64URL)
        try container.encode(Self.pemString(from: der), forKey: .pem)
    }

    private static func pemString(from der: Data) -> String {
        let body = der.base64EncodedString()
            .chunkedForPEM()
            .joined(separator: "\n")
        return """
        -----BEGIN CERTIFICATE-----
        \(body)
        -----END CERTIFICATE-----
        """
    }
}

public nonisolated struct AppAttestDebugAssertionRecord: Encodable, Hashable, Sendable {
    public let credentialName: String
    public let keyId: String
    public let challengeId: String
    public let assertionObject: Data
    public let requestBinding: AppAttestRequestBinding
    public let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case credentialName
        case keyId
        case challengeId
        case assertionObject
        case requestBinding
        case createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(credentialName, forKey: .credentialName)
        try container.encode(keyId, forKey: .keyId)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encode(assertionObject.appAttestBase64URL, forKey: .assertionObject)
        try container.encode(requestBinding, forKey: .requestBinding)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

private nonisolated extension String {
    func chunkedForPEM() -> [String] {
        var chunks: [String] = []
        var index = startIndex
        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: 64, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[index..<nextIndex]))
            index = nextIndex
        }
        return chunks
    }
}
#else
@available(*, unavailable, message: "LocalDebugAppAttestBackend is DEBUG-only and cannot be used in Release builds.")
public final class LocalDebugAppAttestBackend {
    public init() {}
}
#endif
