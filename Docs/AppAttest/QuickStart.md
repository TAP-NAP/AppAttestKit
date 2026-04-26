# Quick Start

Add the package with Xcode:

1. Choose `File > Add Package Dependencies...`.
2. Enter `https://github.com/<owner>/AppAttestKit.git`.
3. Add the `AppAttestKit` product to your app target.

Or add it from `Package.swift`:

```swift
.package(url: "https://github.com/<owner>/AppAttestKit.git", from: "0.1.0")
```

Then import the library:

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

The backend challenge response must provide at least 16 decoded bytes of
base64url challenge data and should include an ISO 8601 UTC `expiresAt`, for
example `2026-04-25T09:30:00Z`.
