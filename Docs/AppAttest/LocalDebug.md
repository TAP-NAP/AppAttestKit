# Local Debug

Source links:

- [LocalDebugAppAttestBackend](../../Sources/AppAttestKit/LocalDebugAppAttestBackend.swift)
- [Example runtime factory](../../Examples/AppAttestDemo/AppAttestDemo/App/AppAttestRuntime.swift)
- [Debug export UI](../../Examples/AppAttestDemo/AppAttestDemo/AppAttestDemo/AppAttestDemoView.swift)

## Purpose

`LocalDebugAppAttestBackend` exists for client development when no server is
available. It uses the fixed challenge string and challenge id:

```text
nearbycommunity
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

## DEBUG Only

`LocalDebugAppAttestBackend` is compiled only under `#if DEBUG`. Release builds
get an unavailable shell with the same name so accidental use fails at compile
time.

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
