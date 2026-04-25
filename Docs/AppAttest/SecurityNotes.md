# Security Notes

Source links:

- [DefaultAppAttestClient](../../Sources/AppAttestKit/DefaultAppAttestClient.swift)
- [Keychain credential store](../../Sources/AppAttestKit/KeychainAppAttestCredentialStore.swift)
- [Error model](../../Sources/AppAttestKit/AppAttestError.swift)
- [HTTP release localhost guard](../../Sources/AppAttestKit/HTTPAppAttestBackend.swift)

## What The Client Can Trust

The client can call Apple App Attest APIs and generate local key handles,
attestation objects, and assertion objects. It cannot decide that an
attestation is trustworthy by itself.

The backend must validate attestation and assertion results. See Apple's
`DCAppAttestService`, "Validating apps that connect to your server", and
"Preparing to use the app attest service" documentation for the underlying
platform contract.

## Why Keychain Stores keyId

The App Attest private key is not stored by this app. Apple keeps it in
system-protected key material and gives the app a `keyId` handle.

The Keychain store saves:

```text
credentialName -> keyId / credentialId / status / environment / createdAt / updatedAt
```

`keyId` is required later by `DCAppAttestService.generateAssertion`. If it is
lost after app restart, the app cannot use the previously registered key and
must run attestation again.

## Challenge And Replay Protection

Production challenges must come from the backend, be short-lived, and be
single-use. The backend must bind each challenge to purpose and credential
name.

Assertions bind the challenge to method, path, sorted query items, body hash,
and optional nonce so an assertion for one request cannot be replayed as
another request.

## Unsupported Devices

`DCAppAttestService.isSupported` can be false. The kit returns
`AppAttestError.unsupportedDevice`; the app and backend decide how to handle
unsupported devices.

## Local Debug Is Not Security

`LocalDebugAppAttestBackend` is for object generation and export only. It does
not replace server validation and cannot be used in Release builds.
