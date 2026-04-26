//
//  AppAttestDemoViewModel.swift
//  AppAttestDemo
//

import Combine
import Foundation
import AppAttestKit

enum AppAttestDemoBackendMode: String, CaseIterable, Identifiable {
    #if DEBUG
    case localDebug
    #endif
    case http

    var id: String { rawValue }

    var title: String {
        switch self {
        #if DEBUG
        case .localDebug:
            "Local Debug Backend"
        #endif
        case .http:
            "HTTP Backend"
        }
    }
}

@MainActor
final class AppAttestDemoViewModel: ObservableObject {
    @Published var selectedBackendMode: AppAttestDemoBackendMode
    @Published var httpBaseURL = AppAttestRuntimeDefaults.httpBaseURLText
    @Published var credentialName = "installation_keyid"
    @Published var requestMethod = "POST"
    @Published var requestPath = "/api/protected/demo"
    @Published var requestBody = #"{"demo":true}"#
    @Published var statusText = "Step 1: enter a credential name.\nStep 2: prepare the credential.\nStep 3: sign one protected request."
    @Published var headersText = ""
    @Published var debugJSON = ""
    @Published var exportDocument: AppAttestCBORDocument?
    @Published var exportFilename = ""
    @Published var isExporterPresented = false
    @Published private(set) var isWorking = false
    @Published private(set) var backendDescription: String

    private var appAttest: any AppAttestClient
    private var activeOperationCount = 0
    private let maxResultLineCount = 12
    #if DEBUG
    private var debugBackend: LocalDebugAppAttestBackend?
    #endif

    init(runtime: AppAttestRuntime) {
        self.appAttest = runtime.client
        self.backendDescription = runtime.backendDescription
        #if DEBUG
        self.debugBackend = runtime.debugBackend
        self.selectedBackendMode = runtime.debugBackend == nil ? .http : .localDebug
        #else
        self.selectedBackendMode = .http
        #endif

        #if DEBUG
        if let mode = runtime.mode,
           let runtimeWithProgress = try? AppAttestRuntimeFactory.make(
            mode: mode,
            progressHandler: { [weak self] message in
                self?.appendProgress(message)
            }
           ) {
            install(runtime: runtimeWithProgress)
        }
        #endif
    }

    var shouldShowHTTPSettings: Bool {
        selectedBackendMode == .http
    }

    var isDebugExportAvailable: Bool {
        #if DEBUG
        return debugBackend != nil
        #else
        return false
        #endif
    }

    func applyBackendSelection() {
        do {
            let mode: AppAttestBackendMode
            switch selectedBackendMode {
            #if DEBUG
            case .localDebug:
                mode = .localDebug
            #endif
            case .http:
                guard let baseURL = URL(string: httpBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw AppAttestError.invalidConfiguration("HTTP Backend URL is invalid.")
                }
                mode = .http(baseURL: baseURL)
            }

            #if DEBUG
            let runtime = try AppAttestRuntimeFactory.make(
                mode: mode,
                progressHandler: { [weak self] message in
                    self?.appendProgress(message)
                }
            )
            #else
            let runtime = try AppAttestRuntimeFactory.make(mode: mode)
            #endif
            install(runtime: runtime)
            headersText = ""
            debugJSON = ""
            statusText = """
            Backend changed.
            \(backendDescription)
            """
        } catch {
            install(runtime: AppAttestRuntimeFactory.fallbackRuntime(error: error))
            statusText = "Backend configuration failed\n\(error.localizedDescription)"
        }
    }

    func prepare() {
        runOperation("Register new key") {
            let credential = try await self.appAttest.prepare(credentialName: self.cleanedCredentialName())
            self.statusText = """
            Registered a new App Attest key.
            credentialName: \(credential.credentialName)
            keyId: \(credential.keyId)
            \(try await self.latestChallengeText())
            """
        }
    }

    func prepareIfNeeded() {
        runOperation("Prepare credential") {
            let credential = try await self.appAttest.prepareIfNeeded(credentialName: self.cleanedCredentialName())
            self.statusText = """
            Credential is ready.
            credentialName: \(credential.credentialName)
            keyId: \(credential.keyId)
            \(try await self.latestChallengeText())
            """
        }
    }

    func generateAssertion() {
        runOperation("Sign protected request") {
            let request = AppAttestProtectedRequest(
                method: self.requestMethod,
                path: self.cleanedRequestPath(),
                body: Data(self.requestBody.utf8)
            )
            let envelope = try await self.appAttest.generateAssertion(
                credentialName: self.cleanedCredentialName(),
                request: request
            )
            var urlRequest = URLRequest(url: self.demoURL(path: request.path))
            try envelope.applyHeaders(to: &urlRequest)
            self.headersText = Self.formatHeaders(urlRequest.allHTTPHeaderFields ?? [:])
            self.statusText = """
            Protected request headers are ready.
            credentialName: \(envelope.credentialName)
            challengeId: \(envelope.challengeId)
            """
        }
    }

    func refreshStatus() {
        runOperation("Check status") {
            let name = try self.cleanedCredentialName()
            let status = try await self.appAttest.status(credentialName: name)
            self.statusText = """
            Credential status:
            credentialName: \(name)
            status: \(status.rawValue)
            """
        }
    }

    func reset() {
        runOperation("Reset local credential") {
            let name = try self.cleanedCredentialName()
            try await self.appAttest.reset(credentialName: name)
            self.statusText = """
            Local credential metadata was reset.
            credentialName: \(name)
            Run Prepare Credential before signing requests again.
            """
            self.headersText = ""
        }
    }

    func exportDebugJSON() {
        #if DEBUG
        guard let debugBackend else {
            debugJSON = "No DEBUG local backend is active."
            return
        }

        runOperation("Export debug JSON") {
            self.debugJSON = try await debugBackend.exportDebugJSONString()
        }
        #endif
    }

    func handleExportResult(_ result: Result<URL, any Error>) {
        let filename = exportFilename
        switch result {
        case .success(let url):
            statusText = "Saved \(filename)\n\(url.lastPathComponent)"
        case .failure(let error):
            statusText = "Save \(filename) failed\n\(error.localizedDescription)"
        }
    }

    func saveAttestationObject() {
        #if DEBUG
        guard let debugBackend else {
            statusText = "No DEBUG local backend is active."
            return
        }

        runOperation("Prepare attestationObject file") {
            let data = try await debugBackend.latestAttestationObject()
            self.exportDocument = AppAttestCBORDocument(data: data)
            self.exportFilename = "attestationObject.cbor"
            self.isExporterPresented = true
            self.statusText = "Choose where to save attestationObject.cbor."
        }
        #endif
    }

    func saveAssertionObject() {
        #if DEBUG
        guard let debugBackend else {
            statusText = "No DEBUG local backend is active."
            return
        }

        runOperation("Prepare assertionObject file") {
            let data = try await debugBackend.latestAssertionObject()
            self.exportDocument = AppAttestCBORDocument(data: data)
            self.exportFilename = "assertionObject.cbor"
            self.isExporterPresented = true
            self.statusText = "Choose where to save assertionObject.cbor."
        }
        #endif
    }

    func saveAssertionClientData() {
        #if DEBUG
        guard let debugBackend else {
            statusText = "No DEBUG local backend is active."
            return
        }

        runOperation("Prepare assertion client data file") {
            let data = try await debugBackend.latestAssertionClientData()
            self.exportDocument = AppAttestCBORDocument(data: data)
            self.exportFilename = "assertionClientData.bin"
            self.isExporterPresented = true
            self.statusText = "Choose where to save assertionClientData.bin."
        }
        #endif
    }

    private func cleanedCredentialName() throws -> String {
        let name = credentialName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw AppAttestError.invalidConfiguration("credentialName cannot be empty.")
        }
        return name
    }

    private func cleanedRequestPath() -> String {
        let path = requestPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty {
            return "/"
        }
        return path.hasPrefix("/") ? path : "/\(path)"
    }

    private func demoURL(path: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "example.com"
        components.path = path
        return components.url ?? URL(string: "https://example.com/")!
    }

    private func install(runtime: AppAttestRuntime) {
        appAttest = runtime.client
        backendDescription = runtime.backendDescription
        #if DEBUG
        debugBackend = runtime.debugBackend
        #endif
    }

    private func setResult(_ text: String) {
        statusText = text
    }

    #if DEBUG
    private func appendProgress(_ message: String) {
        let nextLine = "-> \(message)"
        let lines = (statusText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) + [nextLine])
            .suffix(maxResultLineCount)
        statusText = lines.joined(separator: "\n")
    }
    #endif

    private func latestChallengeText() async throws -> String {
        #if DEBUG
        guard let debugBackend else {
            return "challenge: issued by HTTP Backend"
        }
        let challenge = try await debugBackend.latestChallenge()
        let challengeString = String(data: challenge.challenge, encoding: .utf8) ?? challenge.challenge.appAttestBase64URL
        return """
        challengeId: \(challenge.challengeId)
        challenge: \(challengeString)
        """
        #else
        return "challenge: issued by HTTP Backend"
        #endif
    }

    private func runOperation(_ label: String, operation: @escaping () async throws -> Void) {
        Task { @MainActor in
            activeOperationCount += 1
            isWorking = activeOperationCount > 0
            setResult("\(label)...")

            defer {
                activeOperationCount -= 1
                isWorking = activeOperationCount > 0
            }

            do {
                try await operation()
            } catch {
                setResult("\(label) failed\n\(error.localizedDescription)")
            }
        }
    }

    private static func formatHeaders(_ headers: [String: String]) -> String {
        headers
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }
}
