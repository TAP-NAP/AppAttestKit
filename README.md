# AppAttestKit

AppAttestKit is a Swift Package for iOS App Attest client flows. It owns
attestation and assertion calls, the backend protocol, an HTTP backend adapter,
Keychain credential metadata storage, request binding, DEBUG-only local backend
support, and export helpers for debugging.

The package target imports only `Foundation`, `DeviceCheck`, `Security`, and
`CryptoKit`. UI, backend selection, result panels, and file export live in the
example app at `Examples/AppAttestDemo`.

## How To Use

### Add With Xcode

1. Open your app project in Xcode.
2. Choose `File > Add Package Dependencies...`.
3. Enter the repository URL:

   ```text
   https://github.com/<owner>/AppAttestKit.git
   ```

4. Add the `AppAttestKit` library product to your app target.

For local development, choose `File > Add Packages... > Add Local...` and select
this repository root.

### Add With Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/<owner>/AppAttestKit.git", from: "0.1.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "AppAttestKit", package: "AppAttestKit")
        ]
    )
]
```

### Minimal Client Flow

```swift
import AppAttestKit

let backend = try HTTPAppAttestBackend(
    baseURL: URL(string: "https://api.example.com")!
)
let appAttest = DefaultAppAttestClient(backend: backend)

let credential = try await appAttest.prepareIfNeeded(
    credentialName: "installation_keyid"
)

let protectedRequest = AppAttestProtectedRequest(
    method: "POST",
    path: "/api/protected",
    body: bodyData
)

let envelope = try await appAttest.generateAssertion(
    credentialName: credential.credentialName,
    request: protectedRequest
)

var request = URLRequest(url: URL(string: "https://api.example.com/api/protected")!)
try envelope.applyHeaders(to: &request)
```

Apps do not need to store Apple App Attest `keyId` manually. AppAttestKit stores
credential metadata in Keychain and reuses it by `credentialName`.

## Server Contract

Default HTTP endpoints:

- `POST /app-attest/challenges`
- `POST /app-attest/attestations`
- `POST /app-attest/credentials/status`

Challenge request:

```json
{
  "purpose": "attestation",
  "credentialName": "installation_keyid"
}
```

Challenge response:

```json
{
  "challengeId": "server-challenge-id",
  "challenge": "base64url-random-bytes",
  "expiresAt": "2026-04-25T09:30:00Z"
}
```

Wire format:

- `challenge`, `attestationObject`, and `assertionObject` are base64url without padding.
- `expiresAt` is an ISO 8601 UTC timestamp parseable by Swift `.iso8601`, for example `2026-04-25T09:30:00Z`.
- `challengeId` is server state. It identifies the challenge record and should be single-use.
- `challenge` is random byte data. The client hashes it into Apple App Attest calls.

Assertion headers applied by `AppAttestAssertionEnvelope.applyHeaders(to:)`:

```text
X-App-Attest-Credential-Name
X-App-Attest-Key-Id
X-App-Attest-Challenge-Id
X-App-Attest-Assertion
X-App-Attest-Request-Binding
```

The server remains the security authority. It must validate attestation objects,
assertion signatures, app identifiers, App Attest environment, challenges,
request binding, public keys, and sign counters.

## Credential State

The public API only accepts `credentialName: String`. AppAttestKit does not add
subject, user id, install id, tenant id, or other business identity concepts.

`revoked` means the server no longer accepts a credential/key for assertions.
It is not a way to repair an untrusted device. If the server decides the device
or environment is untrusted, it should reject new attestation registration too.
The client-side revoked status is only a local cache that avoids known-bad work.

## Local Debug

`LocalDebugAppAttestBackend` exists only in DEBUG builds. It uses the fixed
challenge id and challenge string `nearbycommunity`, accepts local registrations,
and exports generated objects for inspection.

Local debug challenges use a long expiration time, currently 24 hours, so manual
testing and export flows do not fail due to short-lived challenge expiry.
Production servers should still issue short-lived, single-use challenges.

Release builds cannot use the local debug backend and reject HTTP backend hosts
that resolve to localhost, IPv4 `127.0.0.0/8`, IPv6 loopback, or `.local`.

## Documentation

- [Quick Start](Docs/AppAttest/QuickStart.md)
- [Client Usage](Docs/AppAttest/ClientUsage.md)
- [Credential Name Guide](Docs/AppAttest/CredentialNameGuide.md)
- [Backend Contract](Docs/AppAttest/BackendContract.md)
- [Local Debug](Docs/AppAttest/LocalDebug.md)
- [Security Notes](Docs/AppAttest/SecurityNotes.md)

## To Do

- Key Rotation: consider a future explicit `rotationRequired` or `expired`
  server status so routine key renewal is not conflated with security revocation.
