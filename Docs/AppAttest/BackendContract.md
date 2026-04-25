# Backend Contract

Source links:

- [AppAttestBackend](../../Sources/AppAttestKit/AppAttestProtocols.swift)
- [HTTPAppAttestBackend](../../Sources/AppAttestKit/HTTPAppAttestBackend.swift)
- [Models](../../Sources/AppAttestKit/AppAttestModels.swift)

## Backend Boundary

All server communication goes through `AppAttestBackend`:

```swift
func requestChallenge(_ request: AppAttestChallengeRequest) async throws -> AppAttestChallenge
func registerAttestation(_ request: AppAttestRegistrationRequest) async throws -> AppAttestRegistrationResult
func credentialStatus(_ request: AppAttestCredentialStatusRequest) async throws -> AppAttestServerCredentialStatus
func recordAssertionResult(_ record: AppAttestAssertionRecord) async
```

## Challenge Endpoint

Default path: `POST /app-attest/challenges`

Request:

```json
{
  "purpose": "attestation",
  "credentialName": "installation_keyid"
}
```

Response:

```json
{
  "challengeId": "server-challenge-id",
  "challenge": "base64url-random-bytes",
  "expiresAt": "2026-04-24T13:00:00Z"
}
```

`challengeId` identifies server-side challenge state. `challenge` is the random
byte payload that the client hashes into Apple App Attest calls. Production
challenges must be short-lived and single-use.

## Attestation Endpoint

Default path: `POST /app-attest/attestations`

Request:

```json
{
  "credentialName": "installation_keyid",
  "keyId": "apple-key-id",
  "challengeId": "server-challenge-id",
  "attestationObject": "base64url-attestation-object"
}
```

Response:

```json
{
  "credentialId": "server-credential-id",
  "status": "accepted"
}
```

The server validates the Apple attestation object, app identifier, App Attest
environment, challenge, public key, and initial sign counter before returning
`accepted`.

## Credential Status Endpoint

Default path: `POST /app-attest/credentials/status`

Request:

```json
{
  "credentialName": "installation_keyid",
  "keyId": "apple-key-id"
}
```

Response body is one of:

```json
"accepted"
```

```json
"revoked"
```

```json
"unknown"
```

## Protected Business Requests

`AppAttestAssertionEnvelope.applyHeaders(to:)` sets:

```text
X-App-Attest-Credential-Name
X-App-Attest-Key-Id
X-App-Attest-Challenge-Id
X-App-Attest-Assertion
X-App-Attest-Request-Binding
```

The server verifies the assertion signature with the registered public key,
checks the sign counter, confirms the challenge is valid and unused, confirms
the credential name matches the registered key, and recomputes request binding.

## Release HTTP Guard

Release builds refuse HTTP backends whose host is `localhost`, `127.0.0.1`,
`::1`, or ends with `.local`.
