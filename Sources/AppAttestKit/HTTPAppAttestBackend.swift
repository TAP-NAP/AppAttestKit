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
// SAFETY: This value type stores immutable configuration. `URLSession` is safe
// to share, and callers must not mutate injected encoders/decoders after init.
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
        if Self.isForbiddenReleaseBackend(baseURL) {
            throw AppAttestError.releaseLocalBackendForbidden(
                "Release builds require an HTTPS App Attest backend and cannot use localhost, loopback, or .local hosts."
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

    public static func isForbiddenReleaseBackend(_ url: URL) -> Bool {
        url.scheme?.lowercased() != "https" || isForbiddenReleaseHost(url)
    }

    public static func isForbiddenReleaseHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        return host == "localhost"
            || isIPv4Loopback(host)
            || isIPv6Loopback(host)
            || host.hasSuffix(".local")
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

    func endpoint(_ path: String) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }

        components.percentEncodedPath = Self.joinPercentEncodedPath(
            base: components.percentEncodedPath,
            path: path
        )
        return components.url ?? baseURL
    }

    private static func isIPv4Loopback(_ host: String) -> Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else {
            return false
        }

        let values = octets.compactMap { UInt8($0) }
        return values.count == 4 && values[0] == 127
    }

    private static func isIPv6Loopback(_ host: String) -> Bool {
        host == "::1" || host == "0:0:0:0:0:0:0:1"
    }

    private static func joinPercentEncodedPath(base: String, path: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        switch (trimmedBase.isEmpty, trimmedPath.isEmpty) {
        case (true, true):
            return ""
        case (true, false):
            return "/\(trimmedPath)"
        case (false, true):
            return "/\(trimmedBase)"
        case (false, false):
            return "/\(trimmedBase)/\(trimmedPath)"
        }
    }
}
