# sealed_trace example

A one-screen tour of the `sealed_trace` SDK:

- log at all six levels;
- log an event with personal data and see that it is masked;
- change `minLevel` or switch the SDK off;
- flush, and clear local logs;
- the Dio interceptor;
- the live diagnostics counters.

```sh
cd example
flutter run            # any device: Android, iOS, web, Windows, macOS, Linux
```

## It runs offline

Uploads go to a **mock ingest server inside the app**, plugged in through
`UploadConfig(httpClientAdapter: ...)`. It accepts every envelope and lists
what it received.

Only the envelope's clear fields can be shown. The app holds just a public
key, so nobody can decrypt the logs on the device, and that includes this app.

The Dio demo calls a mock API. One button, **"Real call to httpbin.org
(optional)"**, sends a single real request to the public echo service
`httpbin.org`. That request needs network access and is never sent unless you
tap the button.

## No real keys

- `apiKey` is a placeholder.
- `lib/src/demo_key.dart` holds a **demo-only public key**. Its private key
  was never saved, so nothing sealed with it can ever be opened.

To try a real server, replace `baseUrl`, `projectId`, `apiKey` and
`publicKeyPem` with your project's values from the SealedTrace console, and
remove `httpClientAdapter`.

## Platform setup used here

- **Android:** `INTERNET` and `ACCESS_NETWORK_STATE` in
  `android/app/src/main/AndroidManifest.xml`.
- **macOS:** `com.apple.security.network.client` in both entitlement files.
- **Web:** nothing extra is needed. Storage is IndexedDB.
