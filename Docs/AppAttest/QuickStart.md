# Quick Start

Add the package and import the library:

```swift
import AppAttestKit
```

Create a backend and client:

```swift
let backend = try HTTPAppAttestBackend(
    baseURL: URL(string: "https://api.example.com")!
)

let appAttest = DefaultAppAttestClient(backend: backend)
```

Prepare one credential name:

```swift
let credential = try await appAttest.prepareIfNeeded(
    credentialName: "installation_keyid"
)
```

Sign a protected request only when the request needs App Attest:

```swift
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

The app never needs to persist Apple `keyId` itself. AppAttestKit stores
credential metadata in Keychain and reuses it by `credentialName`.
