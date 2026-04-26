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
  "expiresAt": "2026-04-25T09:30:00Z"
}
```

`challengeId` identifies server-side challenge state. `challenge` is the random
byte payload that the client hashes into Apple App Attest calls. Production
challenges must be short-lived and single-use.

Wire format:

- `challenge` is base64url without padding.
- Decoded `challenge` bytes must be at least 16 bytes. Production backends
  should use cryptographically random challenge bytes.
- `expiresAt` is optional but recommended. When present, it must be an ISO 8601
  UTC timestamp parseable by Swift `.iso8601`, for example
  `2026-04-25T09:30:00Z`.
- The client rejects an expired or too-short challenge before calling Apple App
  Attest APIs.

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

`attestationObject` is base64url without padding. If the server has marked the
device or environment as untrusted, it should reject new registration instead
of asking the client to create another key.

Current protocol note: the backend contract does not yet define rollback for
the case where the server accepts registration but the client fails to save
Keychain credential metadata. Backends that need stronger recovery guarantees
should make registration idempotent or add an explicit cleanup endpoint.

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

`revoked` means the server no longer accepts that credential/key for assertions.
AppAttestKit caches this state locally so the client avoids known-bad assertion
work, but the server remains the authority. Revocation is not a device repair
mechanism.

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

`X-App-Attest-Assertion` and `X-App-Attest-Request-Binding` are base64url
without padding. The request binding encodes method, path, sorted query items,
body hash, challenge hash, and optional nonce.

`recordAssertionResult` is an observability hook, not proof that the protected
business request was delivered or accepted. Production servers should record
assertion use when they validate the protected request itself.

Current request binding treats `nil` body as an empty body. If your backend
needs to distinguish those cases, keep the server contract versioned before
adding a body-presence field.

## Release HTTP Guard

Release builds require HTTPS. They also refuse HTTP backends whose host is
`localhost`, any IPv4 `127.0.0.0/8` loopback address, IPv6 loopback (`::1` or
`0:0:0:0:0:0:0:1`), or ends with `.local`.
