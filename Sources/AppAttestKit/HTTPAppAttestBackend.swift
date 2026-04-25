//
//  HTTPAppAttestBackend.swift
//  AppAttestDemo
//

import Foundation

public nonisolated struct HTTPAppAttestBackendPaths: Hashable {
    public let challenges: String
    public let attestations: String
    public let credentialStatus: String

    public init(
        challenges: String = "/app-attest/challenges",
        attestations: String = "/app-attest/attestations",
        credentialStatus: String = "/app-attest/credentials/status"
    ) {
        self.challenges = challenges
        self.attestations = attestations
        self.credentialStatus = credentialStatus
    }
}

/// HTTP implementation of the App Attest backend boundary.
public nonisolated struct HTTPAppAttestBackend: AppAttestBackend, @unchecked Sendable {
    public typealias HeadersProvider = @Sendable () async throws -> [String: String]

    private let baseURL: URL
    private let paths: HTTPAppAttestBackendPaths
    private let headersProvider: HeadersProvider
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        baseURL: URL,
        paths: HTTPAppAttestBackendPaths = HTTPAppAttestBackendPaths(),
        headersProvider: @escaping HeadersProvider = { [:] },
        urlSession: URLSession = .shared,
        encoder: JSONEncoder = .appAttestCanonical,
        decoder: JSONDecoder = .appAttestDefault
    ) throws {
        #if !DEBUG
        if Self.isForbiddenReleaseHost(baseURL) {
            throw AppAttestError.releaseLocalBackendForbidden(
                "Release builds cannot use localhost, loopback, or .local App Attest backends."
            )
        }
        #endif

        self.baseURL = baseURL
        self.paths = paths
        self.headersProvider = headersProvider
        self.urlSession = urlSession
        self.encoder = encoder
        self.decoder = decoder
    }

    public func requestChallenge(_ request: AppAttestChallengeRequest) async throws -> AppAttestChallenge {
        try await post(path: paths.challenges, body: request)
    }

    public func registerAttestation(_ request: AppAttestRegistrationRequest) async throws -> AppAttestRegistrationResult {
        try await post(path: paths.attestations, body: request)
    }

    public func credentialStatus(_ request: AppAttestCredentialStatusRequest) async throws -> AppAttestServerCredentialStatus {
        try await post(path: paths.credentialStatus, body: request)
    }

    public func recordAssertionResult(_ record: AppAttestAssertionRecord) async {}

    public static func isForbiddenReleaseHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        if host == "localhost" || host.hasSuffix(".local") {
            return true
        }

        // IPv6 loopback: ::1 and its unabbreviated forms
        if host == "::1" || host == "0:0:0:0:0:0:0:1" {
            return true
        }

        // IPv4 loopback: the entire 127.0.0.0/8 block.
        // UInt8(_:) initialiser rejects both non-numeric strings and values outside 0-255,
        // so allSatisfy ensures the host is a syntactically valid dotted-decimal IPv4 address.
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        if components.count == 4,
           components.allSatisfy({ UInt8($0) != nil }),
           let first = UInt8(components[0]),
           first == 127 {
            return true
        }

        return false
    }

    private func post<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request
    ) async throws -> Response {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        for (field, value) in try await headersProvider() {
            request.setValue(value, forHTTPHeaderField: field)
        }

        request.httpBody = try encoder.encode(body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppAttestError.invalidHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw AppAttestError.backendUnavailable(message)
        }

        return try decoder.decode(Response.self, from: data)
    }

    private func endpoint(_ path: String) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }
        // Strip any trailing slash from the base path so the join never produces "//".
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        // Ensure the path segment always starts with "/" before appending.
        components.path = basePath + (path.hasPrefix("/") ? path : "/" + path)
        return components.url ?? baseURL
    }
}
