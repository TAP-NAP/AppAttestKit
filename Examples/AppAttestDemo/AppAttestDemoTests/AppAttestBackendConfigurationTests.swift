//
//  AppAttestBackendConfigurationTests.swift
//  AppAttestDemoTests
//

import XCTest
@testable import AppAttestDemo

@MainActor
final class AppAttestBackendConfigurationTests: XCTestCase {
    func testParsesHTTPMode() throws {
        let mode = try AppAttestBackendConfiguration.parse(
            mode: "http",
            backendURL: "https://api.example.com",
            localChallenge: nil
        )

        guard case .http(let baseURL) = mode else {
            return XCTFail("Expected HTTP backend mode.")
        }
        XCTAssertEqual(baseURL.absoluteString, "https://api.example.com")
    }

    func testRejectsHTTPModeWithoutURL() {
        XCTAssertThrowsError(
            try AppAttestBackendConfiguration.parse(
                mode: "http",
                backendURL: nil,
                localChallenge: nil
            )
        )
    }

    func testParsesLocalDebugModeWithDefaultChallenge() throws {
        let mode = try AppAttestBackendConfiguration.parse(
            mode: "localDebug",
            backendURL: nil,
            localChallenge: nil
        )

        guard case .localDebug(let challenge) = mode else {
            return XCTFail("Expected local debug backend mode.")
        }
        XCTAssertEqual(challenge, "nearbycommunity0123")
    }

    func testRejectsShortLocalDebugChallenge() {
        XCTAssertThrowsError(
            try AppAttestBackendConfiguration.parse(
                mode: "localDebug",
                backendURL: nil,
                localChallenge: "short"
            )
        )
    }
}
