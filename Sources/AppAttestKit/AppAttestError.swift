//
//  AppAttestError.swift
//  AppAttestDemo
//

import Foundation
import Security

/// Typed errors returned by the reusable App Attest layer.
public nonisolated enum AppAttestError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedDevice
    case invalidConfiguration(String)
    case invalidBase64URL(field: String)
    case invalidHTTPResponse
    case backendUnavailable(String)
    case challengeRejected(String)
    case attestationRejected(String)
    case assertionRejected(String)
    case credentialMissing(String)
    case credentialNotReady(String)
    case keychain(status: OSStatus)
    case releaseLocalBackendForbidden(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedDevice:
            return "This device does not support App Attest."
        case .invalidConfiguration(let message):
            return message
        case .invalidBase64URL(let field):
            return "Invalid base64url value for \(field)."
        case .invalidHTTPResponse:
            return "The App Attest backend returned an invalid HTTP response."
        case .backendUnavailable(let message):
            return "The App Attest backend is unavailable: \(message)"
        case .challengeRejected(let message):
            return "The App Attest challenge was rejected: \(message)"
        case .attestationRejected(let message):
            return "The App Attest registration was rejected: \(message)"
        case .assertionRejected(let message):
            return "The App Attest assertion was rejected: \(message)"
        case .credentialMissing(let credentialName):
            return "No App Attest credential exists for \(credentialName). Run prepareIfNeeded first."
        case .credentialNotReady(let credentialName):
            return "App Attest credential '\(credentialName)' is not ready (status may be revoked). Run prepareIfNeeded first."
        case .keychain(let status):
            return "Keychain operation failed with status \(status)."
        case .releaseLocalBackendForbidden(let message):
            return message
        }
    }
}
