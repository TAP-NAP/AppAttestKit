# AppAttestKit

AppAttestKit is a Swift Package for client-side App Attest flows. The package
owns App Attest attestation/assertion calls, backend transport models, an HTTP
backend adapter, Keychain credential metadata storage, request binding, and
DEBUG-only local export support.

The example app lives in `Examples/AppAttestDemo` and imports `AppAttestKit`.
SwiftUI, file export UI, backend selection UI, and result panels are not part
of the library target.

## Install

Swift Package Manager
AppAttestKit may be installed via Swift Package Manager, by pointing to this repo's URL.

## Code Boundaries

- [AppAttestClient](../../Sources/AppAttestKit/AppAttestProtocols.swift) is the public client protocol.
- [DefaultAppAttestClient](../../Sources/AppAttestKit/DefaultAppAttestClient.swift) runs attestation, assertion, and metadata persistence.
- [KeychainAppAttestCredentialStore](../../Sources/AppAttestKit/KeychainAppAttestCredentialStore.swift) stores `credentialName -> keyId` metadata.
- [HTTPAppAttestBackend](../../Sources/AppAttestKit/HTTPAppAttestBackend.swift) is the production HTTP adapter.
- [LocalDebugAppAttestBackend](../../Sources/AppAttestKit/LocalDebugAppAttestBackend.swift) is DEBUG-only fixed-challenge export support.

## Boundary Rule

The public API accepts only `credentialName: String`. AppAttestKit does not
create or interpret business identity. It only uses the string to find saved
credential metadata for one App Attest key.

Apple attests the generated App Attest key. Apple does not attest
`credentialName`; your backend decides how a credential name maps to your own
business rules.

## Primary Documents

- [QuickStart.md](QuickStart.md): minimal setup.
- [ClientUsage.md](ClientUsage.md): public client API examples.
- [CredentialNameGuide.md](CredentialNameGuide.md): credential naming boundary.
- [BackendContract.md](BackendContract.md): HTTP contract and server duties.
- [LocalDebug.md](LocalDebug.md): DEBUG local backend and export format.
- [SecurityNotes.md](SecurityNotes.md): trust boundaries and non-goals.
