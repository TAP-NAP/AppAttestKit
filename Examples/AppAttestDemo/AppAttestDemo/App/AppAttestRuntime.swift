//
//  AppAttestRuntime.swift
//  AppAttestDemo
//

import Foundation
import AppAttestKit

enum AppAttestBackendMode: Hashable {
    case http(baseURL: URL)
    case localDebug(challenge: String)
}

enum AppAttestBackendConfiguration {
    private static let modeKey = "APP_ATTEST_BACKEND_MODE"
    private static let backendURLKey = "APP_ATTEST_BACKEND_URL"
    private static let localChallengeKey = "APP_ATTEST_LOCAL_CHALLENGE"

    static func mode(from bundle: Bundle = .main) throws -> AppAttestBackendMode {
        try parse(
            mode: bundle.appAttestConfigurationValue(for: modeKey),
            backendURL: bundle.appAttestConfigurationValue(for: backendURLKey),
            localChallenge: bundle.appAttestConfigurationValue(for: localChallengeKey)
        )
    }

    static func parse(
        mode rawMode: String?,
        backendURL rawBackendURL: String?,
        localChallenge rawLocalChallenge: String?
    ) throws -> AppAttestBackendMode {
        guard let rawMode,
              !rawMode.isEmpty else {
            throw AppAttestError.invalidConfiguration(
                "Set APP_ATTEST_BACKEND_MODE to http or localDebug."
            )
        }

        switch rawMode {
        case "http":
            guard let rawBackendURL else {
                throw AppAttestError.invalidConfiguration(
                    "Set APP_ATTEST_BACKEND_URL when APP_ATTEST_BACKEND_MODE is http."
                )
            }
            guard let url = URL(string: rawBackendURL),
                  url.scheme?.lowercased() == "https" else {
                throw AppAttestError.invalidConfiguration(
                    "APP_ATTEST_BACKEND_URL must be an https URL."
                )
            }
            return .http(baseURL: url)

        case "localDebug":
            let challenge = rawLocalChallenge ?? LocalDebugAppAttestBackend.defaultChallengeString
            guard Data(challenge.utf8).count >= 16 else {
                throw AppAttestError.invalidConfiguration(
                    "APP_ATTEST_LOCAL_CHALLENGE must be at least 16 bytes."
                )
            }
            return .localDebug(challenge: challenge)

        default:
            throw AppAttestError.invalidConfiguration(
                "APP_ATTEST_BACKEND_MODE must be http or localDebug."
            )
        }
    }
}

struct AppAttestRuntime {
    let mode: AppAttestBackendMode?
    let client: any AppAttestClient
    let backendDescription: String
    let debugBackend: LocalDebugAppAttestBackend?

    init(
        mode: AppAttestBackendMode? = nil,
        client: any AppAttestClient,
        backendDescription: String,
        debugBackend: LocalDebugAppAttestBackend? = nil
    ) {
        self.mode = mode
        self.client = client
        self.backendDescription = backendDescription
        self.debugBackend = debugBackend
    }
}

enum AppAttestRuntimeFactory {
    #if DEBUG
    static func make(
        progressHandler: (@MainActor @Sendable (String) async -> Void)? = nil
    ) throws -> AppAttestRuntime {
        try make(mode: AppAttestBackendConfiguration.mode(), progressHandler: progressHandler)
    }

    static func make(
        mode: AppAttestBackendMode,
        progressHandler: (@MainActor @Sendable (String) async -> Void)? = nil
    ) throws -> AppAttestRuntime {
        switch mode {
        case .localDebug(let challenge):
            let backend = LocalDebugAppAttestBackend(challengeString: challenge)
            return AppAttestRuntime(
                mode: mode,
                client: DefaultAppAttestClient(
                    backend: backend,
                    credentialStore: KeychainAppAttestCredentialStore(),
                    deviceService: DCAppAttestDeviceService(),
                    environment: .development,
                    progressHandler: progressHandler
                ),
                backendDescription: "Local Debug Backend: \(challenge)",
                debugBackend: backend
            )

        case .http(let baseURL):
            let backend = try HTTPAppAttestBackend(baseURL: baseURL)
            let client = DefaultAppAttestClient(
                backend: backend,
                credentialStore: KeychainAppAttestCredentialStore(),
                deviceService: DCAppAttestDeviceService(),
                environment: .production,
                progressHandler: progressHandler
            )

            return AppAttestRuntime(
                mode: mode,
                client: client,
                backendDescription: "HTTP Backend: \(baseURL.absoluteString)",
                debugBackend: nil
            )
        }
    }
    #else
    static func make() throws -> AppAttestRuntime {
        try make(mode: AppAttestBackendConfiguration.mode())
    }

    static func make(mode: AppAttestBackendMode) throws -> AppAttestRuntime {
        switch mode {
        case .localDebug(let challenge):
            let backend = LocalDebugAppAttestBackend(challengeString: challenge)
            return AppAttestRuntime(
                mode: mode,
                client: DefaultAppAttestClient(
                    backend: backend,
                    credentialStore: KeychainAppAttestCredentialStore(),
                    deviceService: DCAppAttestDeviceService(),
                    environment: .development
                ),
                backendDescription: "Local Debug Backend: \(challenge)",
                debugBackend: backend
            )

        case .http(let baseURL):
            let backend = try HTTPAppAttestBackend(baseURL: baseURL)
            let client = DefaultAppAttestClient(
                backend: backend,
                credentialStore: KeychainAppAttestCredentialStore(),
                deviceService: DCAppAttestDeviceService(),
                environment: .production
            )

            return AppAttestRuntime(
                mode: mode,
                client: client,
                backendDescription: "HTTP Backend: \(baseURL.absoluteString)",
                debugBackend: nil
            )
        }
    }
    #endif

    static func fallbackRuntime(error: Error) -> AppAttestRuntime {
        AppAttestRuntime(
            mode: nil,
            client: UnavailableAppAttestClient(error: error),
            backendDescription: "Configuration error: \(error.localizedDescription)",
            debugBackend: nil
        )
    }
}

private actor UnavailableAppAttestClient: AppAttestClient {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func prepare(credentialName: String) async throws -> AppAttestCredential {
        throw error
    }

    func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential {
        throw error
    }

    func generateAssertion(
        credentialName: String,
        request: AppAttestProtectedRequest
    ) async throws -> AppAttestAssertionEnvelope {
        throw error
    }

    func status(credentialName: String) async throws -> AppAttestCredentialStatus {
        throw error
    }

    func reset(credentialName: String) async throws {
        throw error
    }
}

private extension Bundle {
    func appAttestConfigurationValue(for key: String) -> String? {
        guard let rawValue = object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              !trimmedValue.contains("$(") else {
            return nil
        }
        return trimmedValue
    }
}
