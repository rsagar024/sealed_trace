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
- **Readable user names in the console.** `setUser(id, name: ...)` trims the
  name, cuts it to 256 characters and sends it as given in `ctx.userName` and
  `ctx.userDisplayName`, inside the sealed envelope, so the console shows who
  each user is. Blank names are not sent, and `setUser(null)` clears both.
  Only `setUser` sets `userDisplayName`; a value passed to `setContext` is
  ignored. `MaskConfig(maskUserName: true)` sends `***` in `ctx.userName`, and
  `SealedTraceConfig(sendUserDisplayName: false)` never sends
  `userDisplayName`.
- **Never throws, zero cost when disabled.** Every public call is guarded.
  With `enabled: false`, or below `minLevel`, a call returns before anything
  is allocated.
- **On-device masking.**
  - Sensitive keys are replaced: a default list plus your own keys, matched
    ignoring case and `_`, `-`, `.`, plus any key containing a credential
    fragment such as `token`, `secret` or `password`, or ending with `auth`.
  - Patterns are replaced: JWTs, `Bearer` tokens, email, card numbers (Luhn
    or card grouping), coordinates, Indian and US phone numbers, plus your own
    patterns.
  - Header denylist (14 credential headers, plus any header named like a
    sensitive key), URL query and userinfo redaction.
  - String length cap; idempotent; fails closed.
- **Hybrid encryption per batch.**
  - AES-256-GCM with a fresh key, wrapped with the project's RSA-2048 public
    key (RSA-OAEP, SHA-256).
  - Envelope format v1, with known-answer vectors in
    `test/vectors/envelope_vectors.json`.
  - Large batches are sealed in a background isolate on native platforms.
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
