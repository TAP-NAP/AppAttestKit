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
name. Challenge bytes are sent to the client as base64url without padding, and
must decode to at least 16 bytes. `expiresAt` should be an ISO 8601 UTC timestamp such as
`2026-04-25T09:30:00Z`.

Assertions bind the challenge to method, path, sorted query items, body hash,
and optional nonce so an assertion for one request cannot be replayed as
another request.

## Revoked Credentials

`revoked` is a server statement that one credential/key is no longer accepted
for assertions. AppAttestKit caches that state locally to avoid requesting new
assertion challenges for a known-bad credential.

The server remains the authority. If the reason for revocation is that the
device or environment is untrusted, the server should reject future attestation
registration too. Regenerating a key on an untrusted device is not a security
repair.

Routine key renewal is a different policy concern. Track it as Key Rotation;
future versions may add a dedicated `rotationRequired` or `expired` state.

## Known Design Follow-Ups

If server registration succeeds but Keychain metadata saving fails, the current
contract cannot roll back the server-side credential. Future backend contracts
should support idempotent registration or explicit cleanup.

`recordAssertionResult` is not proof that the protected request was delivered.
Treat it as observability/debug data; production authorization should be logged
when the protected endpoint validates the assertion.

The current request binding hashes `nil` body and empty body the same way. Apps
whose server semantics distinguish those cases should adopt a versioned binding
format before adding body-presence metadata.

## Unsupported Devices

`DCAppAttestService.isSupported` can be false. The kit returns
`AppAttestError.unsupportedDevice`; the app and backend decide how to handle
unsupported devices.

## Local Debug Is Not Security

`LocalDebugAppAttestBackend` is for object generation and export only. It does
not replace server validation, even when compiled into a Release build.
