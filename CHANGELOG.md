## 1.0.0

First release.

### Features

- `SealedTrace` facade: `init`, six log levels (`v`, `d`, `i`, `w`, `e`, `f`),
  `log(LogEvent)`, `setUser`, `setContext`, `addMaskKeys`, `addMaskPattern`,
  `flush`, `clearLocalLogs`, `dispose`, `diagnostics`, and the `onException`
  and `onUploadResult` callbacks.
- **Environments.** `SealedTraceEnv.dev`, `.staging`, `.prod`, or any
  environment created on the SealedTrace dashboard, such as
  `SealedTraceEnv('qa')` or `SealedTraceEnv(appFlavor ?? 'dev')` with Flutter
  flavors. Names are 1 to 32 characters of `a-z`, `0-9`, `_` or `-`; any other
  name leaves the SDK disabled. See "Environments & flavors" in the README.
- **Readable user names in the console, opt-in.** `setUser(id, name: ...)`
  trims the name and cuts it to 256 characters. By default it stays on the
  device: `ctx.userName` is `***` and `ctx.userDisplayName` is not sent.
  `SealedTraceConfig(sendUserDisplayName: true)` sends it as
  `ctx.userDisplayName` for the Users tab, and
  `MaskConfig(maskUserName: false)` sends it in `ctx.userName`. Blank names
  are not sent, and `setUser(null)` clears both. Only `setUser` sets
  `userDisplayName`; a value passed to `setContext` is ignored.
- **Never throws, zero cost when disabled.** Every public call is guarded.
  With `enabled: false`, or below `minLevel`, a call returns before anything
  is allocated.
- **On-device masking.**
  - Sensitive keys are replaced: a default list plus your own keys, matched
    ignoring case and `_`, `-`, `.`, plus any key containing a credential
    fragment such as `token`, `secret` or `password`, or ending with `auth`.
  - Patterns are replaced in every string and in map keys: JWTs, `Bearer`
    tokens, prefixed API keys (AWS, Stripe, GitHub, Google, Slack, GitLab),
    IBANs, US SSNs, Aadhaar and PAN numbers, IPv4 and IPv6 addresses, email,
    card numbers (Luhn or card grouping), coordinates, Indian and US phone
    numbers, plus your own patterns.
  - `key=value`, `key: value`, JSON and XML credential pairs are masked in
    every string, log messages included.
  - `MaskConfig(maskUrlPathSegments: true)` masks ids and tokens in URL paths.
  - Header denylist (14 credential headers, plus any header named like a
    sensitive key), URL query and userinfo redaction.
  - String length cap; idempotent; fails closed.
- **Hybrid encryption per batch.**
  - AES-256-GCM with a fresh key, wrapped with the project's RSA-2048 public
    key (RSA-OAEP, SHA-256).
  - Envelope format v2: the clear header (`alg`, `projectId`, `batchId`,
    `createdAt`, `eventCount`) is authenticated as AES-GCM AAD. Known-answer
    vectors in
    `test/vectors/envelope_vectors.json`.
  - Large batches are sealed in a background isolate on native platforms
    and with WebCrypto on the web.
- **Offline storage of ciphertext only.**
  - SQLite (drift) on native platforms, IndexedDB on the web.
  - Retention by count, age and size, with an emergency purge when storage is
    full.
  - Corruption recovery and a memory fallback.
  - The sequence counter persists across restarts.
- **Reliable upload** to `POST {baseUrl}/api/v1/ingest/logs`.
  - At most 50 envelopes and 2 MB per request.
  - Rows are deleted only for `accepted` and `duplicate` ids.
  - Retries use backoff with jitter; dead letters after 5 attempts.
  - 401/403 pause uploads; 413 halves the request; 429 honours `Retry-After`.
  - Triggers: interval, size threshold, app resume, connectivity restored,
    and manual `flush`.
- **`SealedTraceInterceptor` for Dio.**
  - Masked URL, headers and bodies, with truncation after masking.
  - Host allowlist; the SDK's own ingest calls are never logged.
  - The request and response are never altered.
- `UploadConfig.attestationTokenProvider`: an optional app-attestation token
  (Firebase App Check, Play Integrity, App Attest) sent as
  `X-SealedTrace-Attestation` with every upload.
- `UploadConfig.httpClientAdapter`: an optional Dio `HttpClientAdapter` for
  the SDK's own uploads (a proxy, custom certificates, or a mock server; the
  example app uses one).
- **Web page exit.** When the page is hidden or closed, queued events are
  sealed synchronously into a `localStorage` spill (ciphertext only) and moved
  to IndexedDB at the next start.

### Security

- **HTTPS required outside dev/local.** An `http://` `baseUrl` is rejected,
  leaving the SDK disabled and reporting the problem, unless `env` is `dev` or
  `local` or `SealedTraceConfig(allowInsecureHttp: true)` is set. This keeps
  the `X-Api-Key` header off the wire in cleartext and stops a network
  attacker from forging `202` acknowledgements that would delete pending logs.
- **Credential masking covers real-world names.** Key matching ignores
  separators and case and also catches credential fragments, so
  `accessToken`, `id_token`, `client_secret`, `x-auth-token` and `sessionId`
  are masked. JWTs and `Bearer` tokens are masked in every string, including
  JSON values and log messages. The header denylist now covers
  `Proxy-Authorization`, `X-Auth-Token`, `X-CSRF-Token`,
  `X-Amz-Security-Token`, `X-Goog-Api-Key` and similar. Text bodies use the
  same key rules as JSON.
- **Envelope header is authenticated (format v2).** The header fields sent in
  clear are bound to the ciphertext as AES-GCM additional authenticated
  data, so a captured envelope cannot be replayed under a new `batchId`
  (bypassing deduplication) or filed under another `projectId`, `createdAt`
  or `eventCount` without failing decryption. **Servers must decrypt v2
  with the AAD**; see the README and `test/vectors/envelope_vectors.json`.
  A `projectId` containing control characters is now rejected.
- **The API key is documented as publishable, not secret.** It can be
  extracted from any app binary, so it cannot prove who sent an envelope.
  The README's new "Sender authenticity" section lists the server's duties
  (rate limits per key and IP, treating decrypted content as untrusted, key
  rotation) and the optional attestation hook. If the attestation provider
  fails, nothing is sent and no attempt is counted. Examples use `pk_live_…`.
- **User names are private by default.** `MaskConfig.maskUserName` now
  defaults to `true` and `SealedTraceConfig.sendUserDisplayName` to `false`,
  so a name passed to `setUser` is not sent readable unless the app opts in
  (privacy by default, GDPR Art. 25). The dartdoc that said `ctx.userName`
  "stays masked" under the old defaults is corrected.
- **Wider PII and secret detection.** New default patterns for API keys,
  IBAN, SSN, Aadhaar, PAN and IP addresses, each validated (mod-97, Verhoeff,
  SSN ranges, IPv6 parsing) to keep false positives low. The credential pass
  now covers log messages, not only network bodies, and map keys holding PII
  (for example a map keyed by email) are masked. Identity keys such as
  `iban`, `passport`, `aadhaar` and `nationalId` are masked by default.
- **The host app's UI thread is protected from heavy work.** The
  in-memory queue is capped at 8 MiB as well as 5 000 events. Network
  bodies over 256 KB are not parsed, and bodies over 32 KB are parsed and
  masked in a background isolate on native platforms. On the web, large
  batches are encrypted with WebCrypto instead of pure Dart on the main
  thread; its output is byte-identical, checked in Chrome.
