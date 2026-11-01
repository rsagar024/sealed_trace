# sealed_trace example

A one-screen example of the `sealed_trace` SDK talking to your SealedTrace
server:

- **required:** attach a user id and display name with
  `setUser(id, name: ...)`;
- **required:** attach the device context (`deviceId` and `deviceModel`)
  read with `device_info_plus`;
- log at all six levels (`verbose` and `debug` are dropped at `minLevel: info`);
- log an event with personal data and see that it is masked;
- flush, and watch the upload result and the live diagnostics counters.

On start the screen logs one batch and flushes it, so it works without taps.

## 📖 Quick start

1. Add the dependency:
   ```yaml
   dependencies:
     sealed_trace: ^1.0.0
   ```
2. Do the [platform setup](https://github.com/rsagar024/sealed_trace#platform-setup): Android permissions, the macOS entitlement, and CORS on your server for
   the web.
3. At startup, listen for problems, then initialize:
   ```dart
   Future<void> main() async {
     WidgetsFlutterBinding.ensureInitialized();
     SealedTrace.onException = (error, stack) {
       // The SDK never throws into your app; problems are reported here.
     };
     await SealedTrace.init(const SealedTraceConfig(
       baseUrl: 'https://logs.example.com',
       projectId: 'my-project',
       apiKey: 'sk_live_…',
       publicKeyPem: projectPublicKeyPem,
       appName: 'shop',
       env: SealedTraceEnv.prod,
       minLevel: LogLevel.info,
     ));
     runApp(const MyApp());
   }
   ```
4. **Required:** attach the user and the device, right after `init`:
   ```dart
   SealedTrace.setUser('<user id>', name: '<user name>');      // id: opaque, never an email; name: see below
   SealedTrace.setContext({
     'deviceId': '<device id>',       // Android: androidInfo.id · iOS: iosInfo.identifierForVendor
     'deviceModel': '<device model>', // Android: androidInfo.model · iOS: iosInfo.modelName
   });
   ```
   The `name` is trimmed, cut to 256 characters and sent as given in `ctx.userName` (plus `ctx.userDisplayName`
   for the console's Users tab), so the console shows who each user is in the Users tab, the log list and log
   detail. It travels only inside the sealed envelope. Pass a name only if the server may see it, or set
   `MaskConfig(maskUserName: true)` to send `***` in `ctx.userName` instead. `setUser(null)` clears both.

   The console's device card reads these keys, read with
   [`device_info_plus`](https://pub.dev/packages/device_info_plus):

   | Key | Android | iOS |
   |---|---|---|
   | `deviceId` | `androidInfo.id` | `iosInfo.identifierForVendor` |
   | `deviceModel` | `androidInfo.model` | `iosInfo.modelName` |

   - Don't set `platform`, `os`, `appVersion`, `buildNumber`, `locale`, `env` or `network`. The SDK fills them in,
     and its values win over `setContext`.
   - Call both after `await SealedTrace.init(...)`. Before init they do nothing.
   - See `_deviceContext()` in [`lib/main.dart`](lib/main.dart) for the full code.
5. Log anywhere. Every call returns at once and never throws:
   ```dart
   SealedTrace.v('cache', 'hit', meta: {'key': 'home'});
   SealedTrace.d('cache', 'miss');
   SealedTrace.i('auth', 'signed in');
   SealedTrace.w('sync', 'retrying');
   SealedTrace.e('payment', 'charge failed', error: e, stack: s);
   SealedTrace.f('app', 'unrecoverable', error: e, stack: s);
   ```

## Run this example

1. Open `lib/main.dart` and replace the placeholders with your project's
   values from the SealedTrace console:

   | Placeholder | Where it comes from |
   |---|---|
   | `baseUrl` | your SealedTrace server |
   | `projectId` | console, project settings |
   | `projectPublicKeyPem` | console, project encryption key (the **public** key) |

2. **Required:** `main()` attaches the user and the device right after
   `init` (Quick start step 4); see `_deviceContext()` in `lib/main.dart`.

3. Run with your environment's API key. It is passed with `--dart-define` so
   it never lands in source control:

   ```sh
   cd example
   flutter run --dart-define=SEALED_TRACE_API_KEY=<your-api-key>
   ```

   `flutter run --flavor stage` reports the environment `stage`; no flavor
   means `dev`. Use the API key of that environment.

With the placeholders left in, the app still starts, but the SDK stays
uninitialized: `onException` reports the invalid public key and nothing is
sent.

## Integration test

```sh
cd example
flutter test integration_test -d <device>
```

It runs **offline**. The test initializes the SDK itself with a mock ingest
server (`integration_test/mock_ingest.dart`, plugged in through
`UploadConfig(httpClientAdapter: ...)`) and a **demo-only public key**
(`integration_test/demo_key.dart`) whose private key was never saved. It checks
that events are accepted, that sealed envelopes reach the mock server, and
that the SDK reported no problem.

## Platform setup used here

- **Android:** `INTERNET` and `ACCESS_NETWORK_STATE` in
  `android/app/src/main/AndroidManifest.xml`.
- **macOS:** `com.apple.security.network.client` in both entitlement files.
- **Web:** nothing extra is needed. Storage is IndexedDB.
