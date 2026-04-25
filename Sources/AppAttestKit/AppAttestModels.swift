//
//  AppAttestModels.swift
//  AppAttestDemo
//

import CryptoKit
import Foundation

public nonisolated enum AppAttestPurpose: String, Codable, Hashable, Sendable {
    case attestation
    case assertion
}

public nonisolated enum AppAttestEnvironment: String, Codable, Hashable, Sendable {
    case development
    case production
}

public nonisolated enum AppAttestCredentialStatus: String, Codable, Hashable, Sendable {
    case notPrepared
    case ready
    case revoked
    case unknown
}

public nonisolated enum AppAttestRegistrationStatus: String, Codable, Hashable, Sendable {
    case accepted
    case rejected
}

public nonisolated enum AppAttestServerCredentialStatus: String, Codable, Hashable, Sendable {
    case accepted
    case revoked
    case unknown
}

/// Locally stored metadata for a generated App Attest key.
///
/// `credentialName` is caller-defined. AppAttestKit only uses it to find and
/// reuse the saved keyId; it does not interpret business identity.
public nonisolated struct AppAttestCredential: Codable, Hashable, Sendable {
    public let credentialName: String
    public let keyId: String
    public let credentialId: String?
    public let status: AppAttestCredentialStatus
    public let environment: AppAttestEnvironment
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        credentialName: String,
        keyId: String,
        credentialId: String?,
        status: AppAttestCredentialStatus,
        environment: AppAttestEnvironment,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.credentialName = credentialName
        self.keyId = keyId
        self.credentialId = credentialId
        self.status = status
        self.environment = environment
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public nonisolated struct AppAttestChallengeRequest: Codable, Hashable, Sendable {
    public let purpose: AppAttestPurpose
    public let credentialName: String

    public init(purpose: AppAttestPurpose, credentialName: String) {
        self.purpose = purpose
        self.credentialName = credentialName
    }
}

public nonisolated struct AppAttestChallenge: Codable, Hashable, Sendable {
    public let challengeId: String
    public let challenge: Data
    public let expiresAt: Date?

    public init(challengeId: String, challenge: Data, expiresAt: Date?) {
        self.challengeId = challengeId
        self.challenge = challenge
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case challengeId
        case challenge
        case expiresAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.challengeId = try container.decode(String.self, forKey: .challengeId)
        self.challenge = try AppAttestBase64URL.decode(
            try container.decode(String.self, forKey: .challenge),
            field: "challenge"
        )
        self.expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encode(challenge.appAttestBase64URL, forKey: .challenge)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
    }
}

public nonisolated struct AppAttestRegistrationRequest: Encodable, Hashable, Sendable {
    public let credentialName: String
    public let keyId: String
    public let challengeId: String
    public let attestationObject: Data

    public init(
        credentialName: String,
        keyId: String,
        challengeId: String,
        attestationObject: Data
    ) {
        self.credentialName = credentialName
        self.keyId = keyId
        self.challengeId = challengeId
        self.attestationObject = attestationObject
    }

    private enum CodingKeys: String, CodingKey {
        case credentialName
        case keyId
        case challengeId
        case attestationObject
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(credentialName, forKey: .credentialName)
        try container.encode(keyId, forKey: .keyId)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encode(attestationObject.appAttestBase64URL, forKey: .attestationObject)
    }
}

public nonisolated struct AppAttestRegistrationResult: Codable, Hashable, Sendable {
    public let credentialId: String?
    public let status: AppAttestRegistrationStatus

    public init(credentialId: String?, status: AppAttestRegistrationStatus) {
        self.credentialId = credentialId
        self.status = status
    }
}

public nonisolated struct AppAttestCredentialStatusRequest: Codable, Hashable, Sendable {
    public let credentialName: String
    public let keyId: String?

    public init(credentialName: String, keyId: String?) {
        self.credentialName = credentialName
        self.keyId = keyId
    }
}

public nonisolated struct AppAttestQueryItem: Codable, Hashable, Sendable {
    public let name: String
    public let value: String?

    public init(name: String, value: String?) {
        self.name = name
        self.value = value
    }
}

/// Request data that should be bound into an App Attest assertion.
public nonisolated struct AppAttestProtectedRequest: Hashable, Sendable {
    public let method: String
    public let path: String
    public let query: [AppAttestQueryItem]
    public let body: Data?
    public let nonce: String?

    public init(
        method: String,
        path: String,
        query: [AppAttestQueryItem] = [],
        body: Data? = nil,
        nonce: String? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.nonce = nonce
    }

    func binding(challenge: Data) -> AppAttestRequestBinding {
        let sortedQuery = query.sorted {
            if $0.name == $1.name {
                return ($0.value ?? "") < ($1.value ?? "")
            }
            return $0.name < $1.name
        }

        return AppAttestRequestBinding(
            method: method.uppercased(),
            path: path,
            query: sortedQuery,
            bodySHA256: Self.sha256(body ?? Data()),
            challengeSHA256: Self.sha256(challenge),
            nonce: nonce
        )
    }

    private static func sha256(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).appAttestBase64URL
    }
}

public nonisolated struct AppAttestRequestBinding: Codable, Hashable, Sendable {
    public let method: String
    public let path: String
    public let query: [AppAttestQueryItem]
    public let bodySHA256: String
    public let challengeSHA256: String
    public let nonce: String?

    public func canonicalData() throws -> Data {
        try JSONEncoder.appAttestCanonical.encode(self)
    }

    public func clientDataHash() throws -> Data {
        Data(SHA256.hash(data: try canonicalData()))
    }

    public func headerValue() throws -> String {
        try canonicalData().appAttestBase64URL
    }
}

public nonisolated struct AppAttestAssertionEnvelope: Encodable, Hashable, Sendable {
    public let credentialName: String
    public let keyId: String
    public let challengeId: String
    public let assertionObject: Data
    public let requestBinding: AppAttestRequestBinding

    public init(
        credentialName: String,
        keyId: String,
        challengeId: String,
        assertionObject: Data,
        requestBinding: AppAttestRequestBinding
    ) {
        self.credentialName = credentialName
        self.keyId = keyId
        self.challengeId = challengeId
        self.assertionObject = assertionObject
        self.requestBinding = requestBinding
    }

    private enum CodingKeys: String, CodingKey {
        case credentialName
        case keyId
        case challengeId
        case assertionObject
        case requestBinding
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(credentialName, forKey: .credentialName)
        try container.encode(keyId, forKey: .keyId)
        try container.encode(challengeId, forKey: .challengeId)
        try container.encode(assertionObject.appAttestBase64URL, forKey: .assertionObject)
        try container.encode(requestBinding, forKey: .requestBinding)
    }

    /// Applies assertion metadata to a caller-owned business request.
    ///
    /// The kit never intercepts requests automatically; callers opt in by
    /// applying this envelope only to APIs that should be protected.
    public func applyHeaders(to request: inout URLRequest) throws {
        request.setValue(credentialName, forHTTPHeaderField: "X-App-Attest-Credential-Name")
        request.setValue(keyId, forHTTPHeaderField: "X-App-Attest-Key-Id")
        request.setValue(challengeId, forHTTPHeaderField: "X-App-Attest-Challenge-Id")
        request.setValue(assertionObject.appAttestBase64URL, forHTTPHeaderField: "X-App-Attest-Assertion")
        request.setValue(try requestBinding.headerValue(), forHTTPHeaderField: "X-App-Attest-Request-Binding")
    }
}

public nonisolated struct AppAttestAssertionRecord: Encodable, Hashable, Sendable {
    public let credentialName: String
    public let keyId: String
    public let challengeId: String
    public let assertionObject: Data
    public let requestBinding: AppAttestRequestBinding
    public let createdAt: Date

    public init(
        credentialName: String,
        keyId: String,
        challengeId: String,
        assertionObject: Data,
        requestBinding: AppAttestRequestBinding,
        createdAt: Date
    ) {
        self.credentialName = credentialName
        self.keyId = keyId
        self.challengeId = challengeId
        self.assertionObject = assertionObject
        self.requestBinding = requestBinding
        self.createdAt = createdAt
    }

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

public nonisolated extension JSONEncoder {
    static var appAttestCanonical: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var appAttestPretty: JSONEncoder {
        let encoder = JSONEncoder.appAttestCanonical
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public nonisolated extension JSONDecoder {
    static var appAttestDefault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
