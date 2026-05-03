# Client Usage

Source links:

- [AppAttestClient protocol](../../Sources/AppAttestKit/AppAttestProtocols.swift)
- [DefaultAppAttestClient](../../Sources/AppAttestKit/DefaultAppAttestClient.swift)
- [Request and envelope models](../../Sources/AppAttestKit/AppAttestModels.swift)
- [AppAttestDemo usage example](../../Examples/AppAttestDemo/AppAttestDemo/AppAttestDemo/AppAttestDemoViewModel.swift)

## Choose A Credential Name

```swift
let credentialName = "installation_keyid"
```

`credentialName` is a caller-owned lookup name for one App Attest credential.
The kit does not interpret the string as a business identity or create any
business identity for you.

## Register A New Key

```swift
let credential = try await appAttest.prepare(
    credentialName: credentialName
)
```

`prepare(credentialName:)` always creates a new App Attest key, asks Apple to
attest the key, sends the attestation object to the backend, and saves local
metadata only after the backend accepts registration.

## Reuse When Possible

```swift
let credential = try await appAttest.prepareIfNeeded(
    credentialName: credentialName
)
```

`prepareIfNeeded(credentialName:)` returns a ready local credential when one
exists. Otherwise it runs the full attestation flow.

## Generate Assertion For One Request

```swift
let protectedRequest = AppAttestProtectedRequest(
    method: "POST",
    path: "/api/protected",
    body: bodyData
)

let envelope = try await appAttest.generateAssertion(
    credentialName: credentialName,
    request: protectedRequest
)

var request = URLRequest(url: protectedURL)
try envelope.applyHeaders(to: &request)
```

No request is protected automatically. The caller chooses the protected API,
generates an assertion envelope, and applies the returned headers.

Assertion generation requires a fresh backend challenge. If the backend returns
an expired challenge, AppAttestKit throws `AppAttestError.challengeRejected`
before calling `DCAppAttestService.generateAssertion`.

## Status And Reset

```swift
let status = try await appAttest.status(credentialName: credentialName)
try await appAttest.reset(credentialName: credentialName)
```

`reset` deletes local metadata for that credential name only. It does not delete
metadata for any other credential name.

If the backend returns `revoked`, AppAttestKit persists `.revoked` to local
credential metadata. This local state avoids known-bad assertion attempts, but
the server remains the authority.

## Demo Button Mapping

The example app chooses its backend at startup from `APP_ATTEST_BACKEND_MODE`
and related build settings generated into Info.plist. The UI shows the active
backend but does not switch backends at runtime.

- `Prepare Credential`: calls `prepareIfNeeded(credentialName:)`.
- `Register New Key`: calls `prepare(credentialName:)`.
- `Check Status`: calls `status(credentialName:)`.
- `Reset Local Credential`: calls `reset(credentialName:)`.
- `Sign Protected Request`: calls `generateAssertion(credentialName:request:)`.
- `Save Attestation CBOR`: local debug export of the raw attestation object.
- `Export JSON`: local debug export of collected challenge, attestation, and assertion data.
