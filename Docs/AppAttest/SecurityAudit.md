# Security Audit — AppAttestKit (dev branch)

Audited on: 2026-04-25  
Scope: all Swift sources under `Sources/AppAttestKit/` and the `Examples/AppAttestDemo/` demo app.

---

## Summary

| ID | Severity | Area | Title |
|----|----------|------|-------|
| [SA-01](#sa-01) | 🔴 Critical | HTTPAppAttestBackend | No HTTPS enforcement in Release builds |
| [SA-02](#sa-02) | 🔴 Critical | LocalDebugAppAttestBackend | Fixed, non-random challenge leaks into all debug sessions |
| [SA-03](#sa-03) | 🟠 High | DefaultAppAttestClient | `validateChallenge` does not check challenge byte length / entropy |
| [SA-04](#sa-04) | 🟠 High | DefaultAppAttestClient | TOCTOU race in `prepareIfNeeded` can register two keys |
| [SA-05](#sa-05) | 🟠 High | DefaultAppAttestClient | No rollback when server accepts key but Keychain save fails |
| [SA-06](#sa-06) | 🟡 Medium | DefaultAppAttestClient | `generateAssertion` records assertion before caller submits envelope |
| [SA-07](#sa-07) | 🟡 Medium | DefaultAppAttestClient | TOCTOU on revoked-credential write in `status()` |
| [SA-08](#sa-08) | 🟡 Medium | AppAttestRuntimeDefaults | Release default backend URL is hardcoded to `https://example.com` |
| [SA-09](#sa-09) | 🔵 Low | AppAttestModels | `bodySHA256` silently hashes empty data when body is `nil` |
| [SA-10](#sa-10) | 🔵 Low | AppAttestModels | `JSONEncoder.appAttestCanonical` creates a new encoder on every call |
| [SA-11](#sa-11) | 🔵 Low | HTTPAppAttestBackend / KeychainStore | `@unchecked Sendable` bypasses compiler concurrency safety |
| [SA-12](#sa-12) | 🔵 Low | AppAttestDemoViewModel | `activeOperationCount` can diverge if `Task` is cancelled before defer |

---

## Findings

### SA-01 — No HTTPS enforcement in Release builds {#sa-01}

**File:** `Sources/AppAttestKit/HTTPAppAttestBackend.swift`  
**Lines:** 43-48, 73-82

**Description:**  
`isForbiddenReleaseHost` only blocks localhost/loopback/`.local` host names; it does **not** check whether the URL scheme is `https`. A release build configured with `http://api.example.com` passes the guard, allowing attestation and assertion objects to be sent in cleartext. An attacker on the network path can observe or replay the attestation object.

```swift
// HTTPAppAttestBackend.swift – lines 43-48
#if !DEBUG
if Self.isForbiddenReleaseHost(baseURL) {      // only checks host, not scheme
    throw AppAttestError.releaseLocalBackendForbidden(...)
}
#endif

// lines 73-82
public static func isForbiddenReleaseHost(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    return host == "localhost"
        || isIPv4Loopback(host)
        || isIPv6Loopback(host)
        || host.hasSuffix(".local")
    // ↑ scheme is never checked
}
```

**Recommendation:**  
Add a scheme check in `init` for non-DEBUG builds:

```swift
#if !DEBUG
guard baseURL.scheme?.lowercased() == "https" else {
    throw AppAttestError.releaseLocalBackendForbidden(
        "Release builds require an HTTPS App Attest backend URL."
    )
}
if Self.isForbiddenReleaseHost(baseURL) { ... }
#endif
```

---

### SA-02 — Fixed, non-random challenge in `LocalDebugAppAttestBackend` {#sa-02}

**File:** `Sources/AppAttestKit/LocalDebugAppAttestBackend.swift`  
**Lines:** 14-15, 23-41

**Description:**  
`fixedChallengeString = "nearbycommunity"` is used as both the challenge bytes and the `challengeId` for **every** `requestChallenge` call. Three consequences:

1. All sessions use the same challenge bytes, making replay attacks within a debug session trivially possible.
2. The `challengeId` is never unique, so the backend export cannot distinguish individual challenge records.
3. If a developer accidentally submits a DEBUG build, the challenge is immediately predictable by anyone who reads the source code.

```swift
// LocalDebugAppAttestBackend.swift – lines 14-15
public static let fixedChallengeString = "nearbycommunity"

// lines 23-41 — challengeId and challenge bytes are identical across all calls
let challenge = Data(Self.fixedChallengeString.utf8)
let record = AppAttestDebugChallengeRecord(
    challengeId: Self.fixedChallengeString,   // ← always "nearbycommunity"
    challenge: challenge,                      // ← always same bytes
    ...
)
```

**Recommendation:**  
Generate a fresh UUID-based `challengeId` and random 32-byte challenge for each call, even in the debug backend:

```swift
let challengeId = UUID().uuidString
let challenge = (0..<32).map { _ in UInt8.random(in: 0...255) }
```

---

### SA-03 — `validateChallenge` does not check challenge length or entropy {#sa-03}

**File:** `Sources/AppAttestKit/DefaultAppAttestClient.swift`  
**Lines:** 212-222

**Description:**  
`validateChallenge` only inspects `expiresAt`. It does not verify that `challenge.challenge` contains at least a minimum number of bytes. A buggy or malicious server returning an empty or trivially short challenge would pass this check and be handed directly to `DCAppAttestService.attestKey` / `generateAssertion`. Apple's documentation requires the challenge to be a cryptographically random nonce.

```swift
// DefaultAppAttestClient.swift – lines 212-222
private static func validateChallenge(_ challenge: AppAttestChallenge, purpose: AppAttestPurpose) throws {
    guard let expiresAt = challenge.expiresAt else {
        return                             // ← no length check at all
    }
    guard expiresAt > Date() else {
        throw AppAttestError.challengeRejected(...)
    }
    // ← challenge.challenge may be empty; never verified
}
```

**Recommendation:**  
Add a minimum-length guard (Apple recommends ≥ 16 bytes, 32 is conventional):

```swift
guard challenge.challenge.count >= 16 else {
    throw AppAttestError.challengeRejected(
        "\(purpose.rawValue) challenge \(challenge.challengeId) is too short (\(challenge.challenge.count) bytes)."
    )
}
```

---

### SA-04 — TOCTOU race in `prepareIfNeeded` can register duplicate keys {#sa-04}

**File:** `Sources/AppAttestKit/DefaultAppAttestClient.swift`  
**Lines:** 96-107

**Description:**  
`DefaultAppAttestClient` is an `actor`, so callers serialize between actor-isolated calls. However, the actor is **suspended** at every `await` point, allowing other callers to enter. The sequence below shows how two concurrent `prepareIfNeeded` calls can both register a new key:

```
Caller A: await credentialStore.credential(...)  → nil   (actor suspended)
Caller B: await credentialStore.credential(...)  → nil   (actor suspended)
Caller A: resumes → calls prepare() → server registers key-A → saves to Keychain
Caller B: resumes → calls prepare() → server registers key-B → overwrites Keychain with key-B
```

Result: key-A is registered on the server but permanently lost locally; key-B is registered twice on the server if Caller A's `prepare` also ran first.

```swift
// DefaultAppAttestClient.swift – lines 96-107
public func prepareIfNeeded(credentialName: String) async throws -> AppAttestCredential {
    ...
    if let credential = try await credentialStore.credential(named: credentialName),
       credential.status == .ready {
        return credential       // ← TOCTOU: another caller can pass this check concurrently
    }
    return try await prepare(credentialName: credentialName)
}
```

**Recommendation:**  
Track in-flight prepare operations with a dictionary keyed by `credentialName` and return the existing `Task` result to concurrent callers.

---

### SA-05 — No rollback when server accepts key but Keychain save fails {#sa-05}

**File:** `Sources/AppAttestKit/DefaultAppAttestClient.swift`  
**Lines:** 67-93

**Description:**  
In `prepare()`, if `backend.registerAttestation` succeeds but `credentialStore.save` throws, the function rethrows the Keychain error. The server has a permanently registered public key that the client can never retrieve because the `keyId` was not saved. There is no retry, no tombstone, and no way for the caller to recover the orphaned server-side registration.

```swift
// DefaultAppAttestClient.swift – lines 80-93
let result = try await backend.registerAttestation(...)   // server accepts key
guard result.status == .accepted else { ... }

// If the next line throws, keyId is lost forever:
try await credentialStore.save(credential)                 // ← no rollback
return credential
```

**Recommendation:**  
Document this invariant in a `/// - Warning:` doc comment, and/or allow callers to pass a pre-saved credential to `prepare` so that a retry after a Keychain failure can avoid re-registration.

---

### SA-06 — `generateAssertion` records assertion to backend before envelope is used {#sa-06}

**File:** `Sources/AppAttestKit/DefaultAppAttestClient.swift`  
**Lines:** 151-163

**Description:**  
`backend.recordAssertionResult` is called inside `generateAssertion`, before the returned `AppAttestAssertionEnvelope` is actually applied to a network request. If the caller receives the envelope but fails to send it (network error, cancellation, logic bug), the backend still records a successful assertion that was never submitted. This pollutes assertion logs and may create false-positive sign-counter discrepancies.

```swift
// DefaultAppAttestClient.swift – lines 151-163
await backend.recordAssertionResult(
    AppAttestAssertionRecord(...)    // ← recorded here, inside the kit
)
return envelope                     // ← caller may still fail to send this
```

**Recommendation:**  
Either remove `recordAssertionResult` from the client path and let the backend infer assertion usage from protected-endpoint logs, or expose a separate `confirmAssertionSent(envelope:)` method that callers invoke after a successful HTTP response.

---

### SA-07 — TOCTOU on revoked-credential write in `status()` {#sa-07}

**File:** `Sources/AppAttestKit/DefaultAppAttestClient.swift`  
**Lines:** 180-195

**Description:**  
`status()` reads the local credential, queries the backend, and writes back the revoked state. Between the read and the write the actor is suspended at two `await` points. A concurrent `prepare` or `reset` call could change the credential in the store, and the stale revoked snapshot from `status()` would then overwrite it.

```swift
// DefaultAppAttestClient.swift – lines 166-195
let credential = try await credentialStore.credential(...)   // read, actor suspends
let serverStatus = try await backend.credentialStatus(...)   // network, actor suspends
// ↑ credential may have been replaced by now
if serverStatus == .revoked {
    try await credentialStore.save(revokedCredential)        // writes stale snapshot
}
```

**Recommendation:**  
Re-read the credential after the network call completes and guard that it still matches before writing the revoked state.

---

### SA-08 — Release default backend URL hardcoded to `https://example.com` {#sa-08}

**File:** `Examples/AppAttestDemo/AppAttestDemo/App/AppAttestRuntime.swift`  
**Lines:** 124-131

**Description:**  
`AppAttestRuntimeDefaults.mode` returns `https://example.com` for release builds. Any team that copies this example without customizing the default would silently send attestation data to a third-party domain (IANA example domain, not controlled by the developer).

```swift
// AppAttestRuntime.swift – lines 124-131
enum AppAttestRuntimeDefaults {
    static var mode: AppAttestBackendMode {
        #if DEBUG
        .localDebug
        #else
        .http(baseURL: URL(string: "https://example.com")!)   // ← third-party domain
        #endif
    }
}
```

**Recommendation:**  
Add a `#error` compile-time guard so that building in Release without configuring the URL fails loudly:

```swift
#else
// TODO: Replace with your production App Attest backend URL before shipping.
#error("Set AppAttestRuntimeDefaults.mode to your production backend URL before building for release.")
#endif
```

---

### SA-09 — `bodySHA256` silently hashes empty data when body is `nil` {#sa-09}

**File:** `Sources/AppAttestKit/AppAttestModels.swift`  
**Lines:** 208-215

**Description:**  
`AppAttestProtectedRequest.binding(challenge:)` uses `body ?? Data()`, so a `nil` body and an explicit `Data()` (empty body) produce the same `bodySHA256`. A server that treats these as distinct (for example, a PATCH request with an intentionally empty body vs. a PATCH with no body) cannot tell them apart from the binding alone.

```swift
// AppAttestModels.swift – lines 208-215
return AppAttestRequestBinding(
    ...
    bodySHA256: Self.sha256(body ?? Data()),   // nil and empty produce the same hash
    ...
)
```

**Recommendation:**  
Add a `hasBody: Bool` field to `AppAttestRequestBinding` (or keep `bodySHA256` as `String?`), so server-side validation can distinguish the two cases.

---

### SA-10 — `JSONEncoder.appAttestCanonical` creates a new encoder on every call {#sa-10}

**File:** `Sources/AppAttestKit/AppAttestModels.swift`  
**Lines:** 339-345

**Description:**  
`appAttestCanonical` is a `static var` computed property returning a freshly allocated `JSONEncoder` on every access. It is called inside `AppAttestRequestBinding.canonicalData()` and therefore inside `clientDataHash()` and `headerValue()`, which are themselves called for every assertion. This allocates a new `JSONEncoder` on every assertion.

```swift
// AppAttestModels.swift – lines 339-345
public static var appAttestCanonical: JSONEncoder {    // ← computed property, not stored
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}
```

**Recommendation:**  
Change to a `static let`:

```swift
public static let appAttestCanonical: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()
```

Note: `JSONEncoder` is a class and is not `Sendable` by default; verify thread-safety before sharing a single instance across concurrent callers, or keep the computed-property pattern with a clear comment.

---

### SA-11 — `@unchecked Sendable` bypasses Swift concurrency safety {#sa-11}

**Files:**  
- `Sources/AppAttestKit/HTTPAppAttestBackend.swift` — line 25  
- `Sources/AppAttestKit/KeychainAppAttestCredentialStore.swift` — line 13

**Description:**  
Both types are declared `@unchecked Sendable`. While their stored properties appear thread-safe in practice (immutable struct fields, system-level Keychain serialisation), future mutations would not be caught by the compiler. `@unchecked Sendable` also makes API reviewers assume safety has been verified, which may not hold after refactors.

```swift
// HTTPAppAttestBackend.swift – line 25
public nonisolated struct HTTPAppAttestBackend: AppAttestBackend, @unchecked Sendable {

// KeychainAppAttestCredentialStore.swift – line 13
public nonisolated struct KeychainAppAttestCredentialStore: AppAttestCredentialStore, @unchecked Sendable {
```

**Recommendation:**  
Audit all stored properties and, where possible, replace `@unchecked Sendable` with a conformance that the compiler can verify. At minimum, add a `// SAFETY:` comment explaining why `@unchecked` is correct.

---

### SA-12 — `activeOperationCount` can diverge if `Task` is never scheduled {#sa-12}

**File:** `Examples/AppAttestDemo/AppAttestDemo/AppAttestDemo/AppAttestDemoViewModel.swift`  
**Lines:** 296-313

**Description:**  
`activeOperationCount` is incremented synchronously before creating the unstructured `Task`, and decremented inside the `Task`'s `defer`. If system task pressure causes the task to be cancelled before its body ever executes, the decrement never runs and `isWorking` remains `true` permanently.

```swift
// AppAttestDemoViewModel.swift – lines 296-313
private func runOperation(_ label: String, operation: ...) {
    activeOperationCount += 1               // incremented here (synchronous)
    isWorking = activeOperationCount > 0

    Task {
        defer {
            activeOperationCount -= 1       // only decremented if body runs
            isWorking = activeOperationCount > 0
        }
        try await operation()
    }
}
```

**Recommendation:**  
Consider using structured concurrency (`async` function + `TaskGroup`) so the counter lifecycle is tied to the task's lifetime, or handle `Task.isCancelled` explicitly.

---

## Out of Scope

- Server-side attestation object verification (App ID, environment, challenge binding, sign-counter enforcement) — these are the backend's responsibility and are not implemented in this library.
- App Transport Security (ATS) configuration — controlled by the `Info.plist` of the host application, not this library.
