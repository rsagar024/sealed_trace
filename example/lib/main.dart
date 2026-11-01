// A live example of the sealed_trace SDK.
//
// 1. Replace the placeholders below with your project's values from the
//    SealedTrace console.
// 2. Run with your environment's API key:
//
//      flutter run --dart-define=SEALED_TRACE_API_KEY=<your-api-key>
//
// With the placeholders left in, the SDK stays uninitialized, onException
// reports the invalid public key, and nothing is sent.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:sealed_trace/sealed_trace.dart';

// ---------------------------------------------------------------------------
// Placeholders: replace with your project's values.
// ---------------------------------------------------------------------------

/// Your SealedTrace server.
const baseUrl = 'https://YOUR-SEALEDTRACE-SERVER';

/// Project id, from the console's project settings.
const projectId = 'YOUR_PROJECT_ID';

/// Project public key, shared by all environments of the project.
const projectPublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
PASTE_YOUR_PROJECT_PUBLIC_KEY_HERE
-----END PUBLIC KEY-----
''';

// ---------------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Report crashes, as the README recommends.
  FlutterError.onError = (details) {
    SealedTrace.f(
      'flutter',
      details.exceptionAsString(),
      error: details.exception,
      stack: details.stack,
    );
    FlutterError.presentError(details);
  };
  SealedTrace.onException = (error, stack) {
    debugPrint('example: onException: $error');
  };
  SealedTrace.onUploadResult = (r) {
    debugPrint(
      'example: onUploadResult: ${r.outcome.name}: '
      '${r.accepted} accepted, ${r.failed} failed',
    );
  };

  await SealedTrace.init(
    SealedTraceConfig(
      baseUrl: baseUrl,
      projectId: projectId,
      // Passed with --dart-define so the key never lands in source control.
      apiKey: const String.fromEnvironment('SEALED_TRACE_API_KEY'),
      publicKeyPem: projectPublicKeyPem,
      appName: 'sealed_trace_example',
      // `flutter run --flavor stage` reports `stage`; no flavor means dev.
      env: SealedTraceEnv(appFlavor ?? 'dev'),
      minLevel: LogLevel.info,
    ),
  );
  debugPrint('example: init: ${SealedTrace.isInitialized}');

  // User and device info, attached to every later event.
  SealedTrace.setUser('demo-user', name: 'Demo User');
  SealedTrace.setContext(await _deviceContext());

  runApp(const ExampleApp());
}

/// The keys the console's device card reads. `os` and `appVersion` are
/// filled in by the SDK.
Future<Map<String, dynamic>> _deviceContext() async {
  final device = <String, dynamic>{
    'platform': kIsWeb
        ? 'web'
        : Platform.isAndroid
        ? 'android'
        : Platform.isIOS
        ? 'ios'
        : Platform.operatingSystem,
  };
  try {
    if (!kIsWeb && Platform.isAndroid) {
      final a = await DeviceInfoPlugin().androidInfo;
      device['deviceId'] = a.id; // e.g. BE2A.250530.026.F3
      device['deviceModel'] = a.model; // e.g. Pixel 8
    } else if (!kIsWeb && Platform.isIOS) {
      final i = await DeviceInfoPlugin().iosInfo;
      final id = i.identifierForVendor;
      if (id != null) device['deviceId'] = id;
      device['deviceModel'] = i.modelName; // e.g. iPhone 15 Pro
    }
  } catch (e) {
    debugPrint('example: device info failed: $e');
  }
  return device;
}

/// The example application.
class ExampleApp extends StatelessWidget {
  /// Creates the app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'sealed_trace example',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const DemoScreen(),
  );
}

/// Logs, masks and flushes against the configured server.
class DemoScreen extends StatefulWidget {
  /// Creates the screen.
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  Timer? _refresh;
  final _notes = <String>[];

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (!SealedTrace.isInitialized) {
      // No setState inside initState: add the note directly.
      const message =
          'SDK not initialized: fill in the placeholders in lib/main.dart '
          'and pass SEALED_TRACE_API_KEY';
      debugPrint('example: $message');
      _notes.add(message);
      return;
    }
    // Send one batch automatically so the example works without taps.
    unawaited(
      Future<void>(() async {
        _logAll();
        _logPii();
        await _flush();
      }),
    );
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  void _note(String message) {
    debugPrint('example: $message');
    if (!mounted) return;
    setState(() {
      _notes.insert(0, message);
      if (_notes.length > 30) _notes.removeLast();
    });
  }

  void _logAll() {
    SealedTrace.v('demo', 'verbose: dropped (minLevel info)');
    SealedTrace.d('demo', 'debug: dropped (minLevel info)');
    SealedTrace.i('demo', 'info: user opened the demo screen');
    SealedTrace.w('demo', 'warning: retrying a slow request');
    SealedTrace.e(
      'demo',
      'error: payment failed',
      error: StateError('card declined'),
      stack: StackTrace.current,
    );
    SealedTrace.f('demo', 'fatal: example of an unrecoverable error');
    _note('logged six levels (verbose and debug dropped)');
  }

  void _logPii() {
    SealedTrace.i(
      'auth',
      'sign-in for asha@example.com from +91 98765 43210',
      meta: {'password': 'hunter2', 'card': '4111 1111 1111 1111'},
    );
    _note('logged PII: email, phone, password and card are masked');
  }

  Future<void> _flush() async {
    final r = await SealedTrace.flush();
    _note(
      'flush: ${r.outcome.name} (${r.accepted} accepted, ${r.failed} failed)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = SealedTrace.diagnostics;
    return Scaffold(
      appBar: AppBar(title: const Text('sealed_trace example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'init: ${SealedTrace.isInitialized ? 'ready' : 'not initialized'}',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _logAll,
                child: const Text('Log every level'),
              ),
              FilledButton.tonal(
                onPressed: _logPii,
                child: const Text('Log with PII'),
              ),
              OutlinedButton(onPressed: _flush, child: const Text('Flush')),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'accepted ${d.eventsAccepted} · dropped by level '
            '${d.eventsDroppedLevel} · seal failures ${d.sealFailures} · '
            'storage failures ${d.storageFailures} · uploads '
            '${d.uploadAttempts} (failed ${d.uploadFailures})',
          ),
          const Divider(),
          for (final n in _notes) Text('• $n'),
        ],
      ),
    );
  }
}
