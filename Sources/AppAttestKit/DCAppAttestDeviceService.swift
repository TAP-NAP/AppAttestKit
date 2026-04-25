//
//  DCAppAttestDeviceService.swift
//  AppAttestDemo
//

import DeviceCheck
import Foundation

/// Production wrapper around Apple's DCAppAttestService.
public nonisolated final class DCAppAttestDeviceService: AppAttestDeviceService, @unchecked Sendable {
    private let service: DCAppAttestService

    public init(service: DCAppAttestService = .shared) {
        self.service = service
    }

    public var isSupported: Bool {
        service.isSupported
    }

    public func generateKey() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            service.generateKey { keyId, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let keyId {
                    continuation.resume(returning: keyId)
                } else {
                    continuation.resume(throwing: AppAttestError.attestationRejected("Apple returned no key id."))
                }
            }
        }
    }

    public func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            service.attestKey(keyId, clientDataHash: clientDataHash) { attestationObject, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let attestationObject {
                    continuation.resume(returning: attestationObject)
                } else {
                    continuation.resume(throwing: AppAttestError.attestationRejected("Apple returned no attestation object."))
                }
            }
        }
    }

    public func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            service.generateAssertion(keyId, clientDataHash: clientDataHash) { assertionObject, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let assertionObject {
                    continuation.resume(returning: assertionObject)
                } else {
                    continuation.resume(throwing: AppAttestError.assertionRejected("Apple returned no assertion object."))
                }
            }
        }
    }
}
