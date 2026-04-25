//
//  AppAttestBase64URL.swift
//  AppAttestDemo
//

import Foundation

/// Encodes binary App Attest payloads for JSON and HTTP headers.
public nonisolated enum AppAttestBase64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = base64.count % 4
        if padding > 0 {
            base64.append(String(repeating: "=", count: 4 - padding))
        }

        return Data(base64Encoded: base64)
    }

    public static func decode(_ string: String, field: String) throws -> Data {
        guard let data = decode(string) else {
            throw AppAttestError.invalidBase64URL(field: field)
        }
        return data
    }
}

public nonisolated extension Data {
    var appAttestBase64URL: String {
        AppAttestBase64URL.encode(self)
    }
}
