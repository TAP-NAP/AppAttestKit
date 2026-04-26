//
//  AppAttestDemoView.swift
//  AppAttestDemo
//

import SwiftUI
import UniformTypeIdentifiers

struct AppAttestDemoView: View {
    @StateObject private var viewModel: AppAttestDemoViewModel

    init(runtime: AppAttestRuntime) {
        _viewModel = StateObject(
            wrappedValue: AppAttestDemoViewModel(runtime: runtime)
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppAttestResultPanel(
                    statusText: viewModel.statusText,
                    headersText: viewModel.headersText
                )

                Form {
                    Section("Backend") {
                        Picker("Backend", selection: $viewModel.selectedBackendMode) {
                            ForEach(AppAttestDemoBackendMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }

                        if viewModel.shouldShowHTTPSettings {
                            TextField("Base URL", text: $viewModel.httpBaseURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                        }

                        #if DEBUG
                        if viewModel.selectedBackendMode == .localDebug {
                            TextField("Local challenge", text: $viewModel.localChallenge)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        #endif

                        Button {
                            viewModel.applyBackendSelection()
                        } label: {
                            Label("Use Selected Backend", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(viewModel.isWorking)

                        LabeledContent("Active", value: viewModel.backendDescription)
                    }

                    Section {
                        TextField("Credential name", text: $viewModel.credentialName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("1. Credential")
                    } footer: {
                        Text("credentialName is caller-defined. Challenge is issued by the selected backend when Prepare Credential or Register New Key runs.")
                    }

                    Section {
                        Button {
                            viewModel.prepareIfNeeded()
                        } label: {
                            Label("Prepare Credential", systemImage: "checkmark.seal")
                        }
                        .disabled(viewModel.isWorking)

                        Button {
                            viewModel.prepare()
                        } label: {
                            Label("Register New Key", systemImage: "key")
                        }
                        .disabled(viewModel.isWorking)

                        Button {
                            viewModel.refreshStatus()
                        } label: {
                            Label("Check Status", systemImage: "waveform.path.ecg")
                        }
                        .disabled(viewModel.isWorking)

                        Button(role: .destructive) {
                            viewModel.reset()
                        } label: {
                            Label("Reset Local Credential", systemImage: "trash")
                        }
                        .disabled(viewModel.isWorking)
                    } header: {
                        Text("2. Attestation")
                    } footer: {
                        Text("Prepare Credential reuses a saved keyId when possible. Register New Key always creates and registers a fresh App Attest key.")
                    }

                    Section {
                        TextField("Method", text: $viewModel.requestMethod)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        TextField("Path", text: $viewModel.requestPath)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Body", text: $viewModel.requestBody, axis: .vertical)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(2...5)

                        Button {
                            viewModel.generateAssertion()
                        } label: {
                            Label("Sign Protected Request", systemImage: "signature")
                        }
                        .disabled(viewModel.isWorking)
                    } header: {
                        Text("3. Assertion")
                    } footer: {
                        Text("Sign Protected Request generates assertion headers for this one method, path, and body.")
                    }

                    #if DEBUG
                    if viewModel.isDebugExportAvailable {
                        Section("Debug Export") {
                            Button {
                                viewModel.saveAttestationObject()
                            } label: {
                                Label("Save Attestation CBOR", systemImage: "square.and.arrow.down")
                            }
                            .disabled(viewModel.isWorking)

                            Button {
                                viewModel.saveAssertionObject()
                            } label: {
                                Label("Save Assertion CBOR", systemImage: "square.and.arrow.down.on.square")
                            }
                            .disabled(viewModel.isWorking)

                            Button {
                                viewModel.saveAssertionClientData()
                            } label: {
                                Label("Save Assertion Client Data", systemImage: "number")
                            }
                            .disabled(viewModel.isWorking)

                            Button {
                                viewModel.exportDebugJSON()
                            } label: {
                                Label("Export JSON", systemImage: "doc.text")
                            }
                            .disabled(viewModel.isWorking)

                            if !viewModel.debugJSON.isEmpty {
                                Text("Collected local debug challenge, attestation, and assertion artifacts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(viewModel.debugJSON)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    #endif
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("App Attest")
            .navigationBarTitleDisplayMode(.inline)
            .fileExporter(
                isPresented: $viewModel.isExporterPresented,
                document: viewModel.exportDocument,
                contentType: .data,
                defaultFilename: viewModel.exportFilename
            ) { result in
                viewModel.handleExportResult(result)
            }
        }
    }
}

private struct AppAttestResultPanel: View {
    let statusText: String
    let headersText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Result")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(statusText)
                        .textSelection(.enabled)

                    if !headersText.isEmpty {
                        Divider()
                        Text("Assertion headers")
                            .foregroundStyle(.secondary)
                        Text(headersText)
                            .textSelection(.enabled)
                    }
                }
                .font(.system(.caption2, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 156)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
