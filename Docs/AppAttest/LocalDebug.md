# Local Debug

Source links:

- [LocalDebugAppAttestBackend](../../Sources/AppAttestKit/LocalDebugAppAttestBackend.swift)
- [Example runtime factory](../../Examples/AppAttestDemo/AppAttestDemo/App/AppAttestRuntime.swift)
- [Debug export UI](../../Examples/AppAttestDemo/AppAttestDemo/AppAttestDemo/AppAttestDemoView.swift)

## Purpose

`LocalDebugAppAttestBackend` exists for client development when no server is
available. It uses the fixed challenge string and challenge id:

```text
nearbycommunity0123
```

It records locally generated challenges, registrations, and assertions so the
example app can export JSON or raw attestation CBOR.

Local debug challenges return an `expiresAt` about 24 hours in the future. This
keeps manual local testing and export flows from failing due to short challenge
lifetimes. Production servers should still issue short-lived, single-use
challenges.

## Safety Boundary

The local debug backend does not validate production security. It accepts all
registrations and reports accepted status. Real attestation and assertion
verification must happen on a server.

## Availability

`LocalDebugAppAttestBackend` is compiled in Debug and Release builds so local
development and export flows can be exercised from either configuration. It is
still not a production backend and should not replace server-side validation.

The example app selects this backend only when build settings generate
`APP_ATTEST_BACKEND_MODE=localDebug` into Info.plist. Debug uses that mode by
default. Release can also use it for local QA, but only through the same
explicit build setting.

`DefaultAppAttestClient` progress reporting is also DEBUG-only. Release builds
do not expose the progress handler initializer.

## Exported JSON

The debug export includes:

- `challengeId`
- `challenge`
- `purpose`
- `credentialName`
- `keyId`
- `attestationObject`
- `attestationCertificates`
- `assertionObject`
- `requestBinding`
- `expiresAt`
- `createdAt`

Binary fields are base64url encoded. The raw CBOR file export writes exactly
the bytes returned by `DCAppAttestService.attestKey`.
