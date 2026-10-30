## 1.0.0

First release.

### Features

- `SealedTrace` facade: `init`, six log levels (`v`, `d`, `i`, `w`, `e`, `f`),
  `log(LogEvent)`, `setUser`, `setContext`, `addMaskKeys`, `addMaskPattern`,
  `flush`, `clearLocalLogs`, `dispose`, `diagnostics`, and the `onException`
  and `onUploadResult` callbacks.
- **Never throws, zero cost when disabled.** Every public call is guarded.
  With `enabled: false`, or below `minLevel`, a call returns before anything
  is allocated.
- **On-device masking.**
  - Sensitive keys are replaced: an exact, case-insensitive default list plus
    your own keys.
  - Patterns are replaced: email, card numbers (Luhn or card grouping),
    coordinates, Indian and US phone numbers, plus your own patterns.
  - Header denylist, URL query and userinfo redaction.
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

### Known limitations

- The AES-GCM and RSA-OAEP code is this package's own, has not had an
  independent security review, and is not constant-time.
- Up to 2 seconds of events can be lost if the process is killed without a
  lifecycle event.
- Masking has documented gaps. Keys outside the default list (for example
  `authorization`) are not masked in your own metadata unless you add them.
- Not yet verified on Safari, iOS, macOS, Linux, a Windows desktop build, or
  a low-end device. Never run against the production server.
