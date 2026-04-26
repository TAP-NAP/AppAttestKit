//
//  AppAttestRuntime.swift
//  AppAttestDemo
//

import Foundation
import AppAttestKit

enum AppAttestBackendMode: Hashable {
    case http(baseURL: URL)
    #if DEBUG
    case localDebug
    #endif
}

struct AppAttestRuntime {
    let mode: AppAttestBackendMode?
    let client: any AppAttestClient
    let backendDescription: String
    #if DEBUG
    let debugBackend: LocalDebugAppAttestBackend?
    #endif

    #if DEBUG
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
    #else
    init(mode: AppAttestBackendMode? = nil, client: any AppAttestClient, backendDescription: String) {
        self.mode = mode
        self.client = client
        self.backendDescription = backendDescription
    }
    #endif
}

enum AppAttestRuntimeFactory {
    #if DEBUG
    static func make(
        mode: AppAttestBackendMode = AppAttestRuntimeDefaults.mode,
        progressHandler: (@MainActor @Sendable (String) async -> Void)? = nil
    ) throws -> AppAttestRuntime {
        switch mode {
        case .localDebug:
            let backend = LocalDebugAppAttestBackend()
            return AppAttestRuntime(
                mode: mode,
                client: DefaultAppAttestClient(
                    backend: backend,
                    credentialStore: KeychainAppAttestCredentialStore(),
                    deviceService: DCAppAttestDeviceService(),
                    environment: .development,
                    progressHandler: progressHandler
                ),
                backendDescription: "Local Debug Backend",
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
        try make(mode: AppAttestRuntimeDefaults.defaultMode())
    }

    static func make(mode: AppAttestBackendMode) throws -> AppAttestRuntime {
        switch mode {
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
                backendDescription: "HTTP Backend: \(baseURL.absoluteString)"
            )
        }
    }
    #endif

    static func fallbackRuntime(error: Error) -> AppAttestRuntime {
        #if DEBUG
        AppAttestRuntime(
            mode: nil,
            client: UnavailableAppAttestClient(error: error),
            backendDescription: "Configuration error: \(error.localizedDescription)",
            debugBackend: nil
        )
        #else
        AppAttestRuntime(
            mode: nil,
            client: UnavailableAppAttestClient(error: error),
            backendDescription: "Configuration error: \(error.localizedDescription)"
        )
        #endif
    }
}

enum AppAttestRuntimeDefaults {
    static var httpBaseURLText: String {
        #if DEBUG
        "https://example.com"
        #else
        configuredProductionBackendURL?.absoluteString ?? ""
        #endif
    }

    #if DEBUG
    static var mode: AppAttestBackendMode {
        .localDebug
    }
    #else
    static func defaultMode() throws -> AppAttestBackendMode {
        guard let url = configuredProductionBackendURL else {
            throw AppAttestError.invalidConfiguration(
                "Set APP_ATTEST_BACKEND_URL in the app Info.plist before using App Attest in Release."
            )
        }
        return .http(baseURL: url)
    }

    private static var configuredProductionBackendURL: URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "APP_ATTEST_BACKEND_URL") as? String else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              !trimmedValue.contains("$("),
              let url = URL(string: trimmedValue),
              url.scheme?.lowercased() == "https" else {
            return nil
        }
        return url
    }
    #endif
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
