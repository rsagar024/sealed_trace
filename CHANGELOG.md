## 1.0.1

### Fixed

- Web builds are now WASM-compatible. The app version is read through the
  `package_info_plus` platform interface, so `dart:io` no longer enters the
  web import graph. This restores full pub.dev platform-support points.

## 1.0.0

First release.

Get started: create an account and a project at
https://sealedtrace.duckdns.org, the hosted console and ingest server, to get
the project id, API key and public key. See "Getting your keys" in the README.

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
- **Readable user id and name.** `setUser(id, name: ...)` trims the name
  and cuts it to 256 characters. By default the id is sent as `userId` and
  the name as `ctx.userName`, both unmasked; these are the only unmasked
  copies, and the same name in a message, metadata or `setContext` is still
  masked. `MaskConfig(maskUserName: true)` sends `***` in `ctx.userName`
  instead. `SealedTraceConfig(sendUserDisplayName: true)` also sends the name
  as `ctx.userDisplayName` for the Users tab (off by default). Blank names
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
  - Envelope format v3: the clear header (`alg`, `projectId`, `batchId`,
    `createdAt`, `eventCount`, `kid`) is authenticated as AES-GCM AAD. Known-answer
    vectors in
    `test/vectors/envelope_vectors.json`.
  - Large batches are sealed in a background isolate on native platforms
    and with WebCrypto on the web (every asynchronous seal).
- **Offline storage of ciphertext only.**
  - SQLite (drift) on native platforms, IndexedDB on the web.
  - Retention by count, age and size, with an emergency purge when storage is
    full.
  - Corruption recovery and a memory fallback. Copies of a corrupt
    database are deleted after 7 days (at most 3 kept) and by
    `clearLocalLogs`.
  - The sequence counter persists across restarts.
- **Reliable upload** to `POST {baseUrl}/api/v1/ingest/logs`.
  - At most 50 envelopes and 2 MB per request.
  - Rows are deleted only for `accepted` and `duplicate` ids.
  - Retries use backoff with jitter; dead letters after 5 attempts.
  - 401/403 pause uploads and probe again later (1 h, or 5 min without the
    server's JSON body, doubling to 12 h); 413 halves the request; 429
    honours `Retry-After`.
  - Triggers: interval, size threshold, app resume, connectivity restored,
    and manual `flush`.
- **`SealedTraceInterceptor` for Dio.**
  - Masked URL, headers and bodies, with truncation after masking.
  - Host allowlist; the SDK's own ingest calls are never logged.
  - The request and response are never altered.
- `UploadConfig.pinnedSpkiSha256`: optional public-key pinning for the
  ingest server on native platforms, checked before any request bytes are
  sent.
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
- **User names are sent once, not twice.** `SealedTraceConfig.sendUserDisplayName`
  now defaults to `false`, so the `setUser` name is sent only in
  `ctx.userName` (unmasked by default; `MaskConfig(maskUserName: true)` masks
  it). The dartdoc that said `ctx.userName` "stays masked" is corrected.
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
- **Transport hardening.** Uploads never follow redirects (`followRedirects:
  false`, `maxRedirects: 0`); a `3xx`, or a response the browser reached
  through a redirect, counts as a failure and its body is ignored. At most
  256 KB of a response body is read. Optional SPKI pinning
  (`pinnedSpkiSha256`) rejects a mismatching server before the API key or
  envelopes are sent.
- **Timing and retention values are bounded.** `init` raises out-of-range
  values instead of using them: upload `interval` >= 30 s, `backoffBase`
  and `requestTimeout` >= 1 s, retention `maxEvents` and `maxAgeDays` >= 1,
  `maxSizeBytes` >= 64 KB, `purgeInterval` >= 1 min, `deadLetterTtl` >= 0.
  A zero interval or backoff can no longer spin a timer or cause a retry
  storm. Each adjustment is counted in `diagnostics.configValuesAdjusted`
  and printed.
- **Web spill recovery is stricter.** Entries recovered from the
  `localStorage` spill must have the exact key, IV and tag sizes, a
  ciphertext matching its declared size, consistent index columns, a key
  equal to the batch id, the configured `projectId`, and a `createdAt` no
  more than a day ahead. At most the newest 200 are recovered. Dropped
  entries are counted in `diagnostics.spillEntriesRejected`. The README
  now states that the spill is not tamper-proof against same-origin
  scripts.
- **Key material is wiped after use (best effort).** The expanded AES round
  keys, the GHASH key H and its state, the tag mask and keystream, the
  RSA-OAEP DB, masks and EM, the OAEP seed, the background isolate's copy
  of the key and plaintext, and the plaintext buffer are overwritten with
  zeros once sealing is done.
- **Less metadata in the clear.** The plaintext is padded with spaces to a
  Padmé size bucket (at least 256 bytes, at most about 12 % overhead), so the
  ciphertext length no longer reveals the exact size. The stored index no
  longer records sequence ranges, event times or levels (`seqMin`, `seqMax`,
  `minTs`, `maxTs` are 0 and `topLevels` is empty), so a dump of the database
  no longer shows whether a `fatal` occurred. The vectors and their spec are
  updated.
- **Fewer raw identifiers.** New `SealedTrace.pseudonym(value)` gives a
  stable, project-scoped pseudonym (HMAC-SHA256 keyed by the project id) for
  ids such as `deviceId`; the example app now sends its device id that way.
  New `MaskConfig(pseudonymizeUserId: true)` sends the `setUser` id as its
  pseudonym. On the web, `ctx.os` is now only the browser, its major version
  and the OS (`Chrome 157 on Windows`), not up to 120 characters of user
  agent.
- **Envelope v3: key id and larger RSA keys.** Every envelope now carries
  `kid`, the project key's identifier (first 16 bytes of SHA-256 over its DER
  SubjectPublicKeyInfo, base64url), on the wire and as a seventh AAD line, so
  a server can pick the right private key after a key rotation. RSA keys of
  3072 and 4096 bits are accepted; `alg` names the size. Rows that an
  earlier 1.0.0 build (envelope v1) left on the device are still sent as v1,
  exactly as they were sealed (no AAD), as is its `localStorage` spill. The
  SQLite schema moves to version 2 (a nullable `kid` column). **The server
  must accept v3, and v1 for a transition window**; see the README's
  "Server changes".
- **The test key cannot ship.** Release builds (`kReleaseMode`) refuse the
  repository's test RSA key, whose private key is public: `init` reports it
  through `onException` and leaves the SDK disabled. `test/` and `tool/`,
  which hold that private key and a TLS test key, are no longer part of the
  published package.
- **Custom mask patterns can no longer freeze the app.** `extraPatterns` and
  `addMaskPattern` now refuse patterns that can backtrack exponentially:
  nested repetition (`(a+)+`), repeated alternation (`(a|b)*`) and
  backreferences. They are ignored and reported through `onException` with
  the reason. Before, `(a+)+$` blocked the calling thread for about 3 s on
  25 characters, doubling with each extra character. Polynomial patterns
  such as `.*x` are not detected; the README explains how to write safe
  patterns.
- **Web uploads batch again.** The upload cycle bounded its candidate rows
  with `1 << 40`, which dart2js evaluates to 0 (32-bit shifts), so web
  clients sent one envelope per request. The bound is now the 2 MB request
  limit, checked in Chrome, and a test fails on any shift of 32 or more in
  `lib/`.
- **Corrupt-database copies no longer pile up.** When a corrupt
  `sealed_trace.db` is set aside, its `.corrupt-<time>` copy (with `-wal`
  and `-shm`) is now deleted at a later successful open once it is 7 days
  old, at most 3 are kept, and `clearLocalLogs()` deletes them all, so a
  previous user's sealed data does not stay on disk after sign-out.
- **Strict DER parsing.** Public keys (and certificates for pinning) must be
  strict DER: low tag numbers only, definite and minimal lengths of at most
  3 bytes, and INTEGERs without redundant leading zeros. A huge long-form
  length can no longer turn negative under dart2js and throw a `RangeError`;
  malformed input is always a `FormatException`.
- **`setContext` is bounded and cannot set the user name.** The context that
  `setContext` builds up across calls is limited to 100 keys and 16 KB of
  JSON; entries past a limit are dropped (the old value is kept), counted in
  `diagnostics.contextEntriesDropped` and reported once per session.
  `userName`, like `userDisplayName` and the device context keys, is now
  ignored in `setContext`, so it can no longer bypass masking; only `setUser`
  sets it.
- **A 401/403 no longer stops uploads for the whole session.** The pause
  ends by itself and the next cycle probes again: after 1 hour when the
  answer is the ingest server's (a JSON object body), after 5 minutes when it
  is not (a captive portal, WAF or misrouted CDN), doubling on each repeat up
  to 12 hours. A successful upload resets it. No attempt is counted, and the
  failure is reported once per episode.
- **Less timing exposure in the crypto.** GHASH's multiply and reduction
  are branch-free (mask-based). On the web every asynchronous seal now uses
  WebCrypto, not only batches over 8 KB. New
  `SealedTraceConfig.aesGcmEncryptor` plugs in a platform AES-256-GCM on
  native platforms; it must pass a known-answer self-test at `init` and
  falls back to the built-in cipher per call if it fails.
