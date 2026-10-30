// A tour of the sealed_trace SDK. It runs fully offline by default: uploads
// go to a mock ingest server inside the app, and the Dio demo calls a mock
// API. One optional button sends a real request to a public echo service.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:sealed_trace/sealed_trace.dart';

import 'src/demo_key.dart';
import 'src/mock_servers.dart';

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
  runApp(const ExampleApp());
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

/// One screen with every feature of the SDK.
class DemoScreen extends StatefulWidget {
  /// Creates the screen.
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  final _ingest = MockIngestAdapter();
  final _messages = <String>[];
  LogLevel _minLevel = LogLevel.verbose;
  bool _enabled = true;
  bool _busy = false;
  String _lastUpload = 'none yet';
  DiagnosticSnapshot _diagnostics = SealedTrace.diagnostics;
  Timer? _refresh;

  // An app Dio with the interceptor, talking to a mock API.
  late final Dio _apiDio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
    ..httpClientAdapter = MockApiAdapter()
    ..interceptors.add(SealedTraceInterceptor());

  // A second Dio for the optional real request to a public echo service.
  late final Dio _echoDio = Dio()..interceptors.add(SealedTraceInterceptor());

  @override
  void initState() {
    super.initState();
    _ingest.onReceived = () {
      if (mounted) setState(() {});
    };
    SealedTrace.onException = (error, _) => _note('onException: $error');
    SealedTrace.onUploadResult = (r) {
      _lastUpload =
          '${r.outcome.name}: ${r.accepted} accepted, ${r.failed} failed';
      if (mounted) setState(() {});
    };
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _diagnostics = SealedTrace.diagnostics);
    });
    unawaited(_start());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    unawaited(SealedTrace.dispose());
    super.dispose();
  }

  /// Changing the configuration needs dispose, then init.
  Future<void> _start() async {
    setState(() => _busy = true);
    await SealedTrace.dispose();
    await SealedTrace.init(
      SealedTraceConfig(
        baseUrl: 'https://ingest.mock.invalid', // never contacted in mock mode
        projectId: 'demo-project',
        apiKey: 'demo-api-key', // placeholder, not a real key
        publicKeyPem: demoPublicKeyPem,
        appName: 'sealed_trace_example',
        env: SealedTraceEnv.dev,
        minLevel: _minLevel,
        enabled: _enabled,
        uploadConfig: UploadConfig(httpClientAdapter: _ingest),
      ),
    );
    if (SealedTrace.isInitialized) {
      SealedTrace.setUser('demo-user-1');
      SealedTrace.setContext({'screen': 'demo'});
    }
    _note(
      'init: ${SealedTrace.isInitialized ? 'ready' : 'not initialized'}'
      ' (enabled: $_enabled, minLevel: ${_minLevel.name})',
    );
    if (mounted) setState(() => _busy = false);
  }

  void _note(String message) {
    debugPrint('example: $message');
    if (!mounted) return;
    setState(() {
      _messages.insert(0, message);
      if (_messages.length > 30) _messages.removeLast();
    });
  }

  void _logAll() {
    SealedTrace.v('demo', 'verbose: cache lookup for key home');
    SealedTrace.d('demo', 'debug: cache miss');
    SealedTrace.i('demo', 'info: user opened the demo screen');
    SealedTrace.w('demo', 'warning: retrying a slow request');
    SealedTrace.e(
      'demo',
      'error: payment failed',
      error: StateError('card declined'),
      stack: StackTrace.current,
    );
    SealedTrace.f('demo', 'fatal: example of an unrecoverable error');
    _note('logged one event at each of the six levels');
  }

  void _logPii() {
    SealedTrace.i(
      'auth',
      'sign-in for asha@example.com from +91 98765 43210',
      meta: {
        'password': 'hunter2',
        'card': '4111 1111 1111 1111',
        'plan': 'pro',
      },
    );
    _note(
      'logged PII: email, phone, password and card are masked to *** '
      'before the event is queued',
    );
  }

  Future<void> _flush() async {
    final r = await SealedTrace.flush();
    _note('flush: ${r.outcome.name} (${r.accepted} accepted)');
  }

  Future<void> _clear() async {
    await SealedTrace.clearLocalLogs();
    _note('clearLocalLogs: everything stored on this device was removed');
  }

  Future<void> _mockApiCall() async {
    try {
      final r = await _apiDio.post<Object>(
        '/v1/sign-in',
        data: {'email': 'asha@example.com', 'password': 'hunter2'},
        options: Options(headers: {'Authorization': 'Bearer demo-secret'}),
      );
      _note(
        'mock API: ${r.statusCode}. The network event masks the password, '
        'the token, the email and the Authorization header',
      );
    } on DioException catch (e) {
      _note('mock API failed: ${e.type.name}');
    }
  }

  Future<void> _echoCall() async {
    try {
      final r = await _echoDio.get<Object>(
        'https://httpbin.org/anything',
        queryParameters: {'token': 'not-a-real-token', 'page': 2},
      );
      _note('echo: ${r.statusCode} (the logged URL shows token=***)');
    } on DioException catch (e) {
      _note('echo failed: ${e.type.name} (offline?)');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _diagnostics;
    return Scaffold(
      appBar: AppBar(title: const Text('sealed_trace example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Configuration',
            children: [
              SwitchListTile(
                title: const Text('enabled'),
                value: _enabled,
                onChanged: _busy
                    ? null
                    : (v) {
                        _enabled = v;
                        unawaited(_start());
                      },
              ),
              ListTile(
                title: const Text('minLevel'),
                trailing: DropdownButton<LogLevel>(
                  value: _minLevel,
                  onChanged: _busy
                      ? null
                      : (v) {
                          if (v == null) return;
                          _minLevel = v;
                          unawaited(_start());
                        },
                  items: [
                    for (final level in LogLevel.values)
                      DropdownMenuItem(value: level, child: Text(level.name)),
                  ],
                ),
              ),
            ],
          ),
          _Section(
            title: 'Log',
            children: [
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
                  OutlinedButton(
                    onPressed: _clear,
                    child: const Text('Clear local logs'),
                  ),
                ],
              ),
            ],
          ),
          _Section(
            title: 'Dio interceptor',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: _mockApiCall,
                    child: const Text('Mock API call'),
                  ),
                  OutlinedButton(
                    onPressed: _echoCall,
                    child: const Text('Real call to httpbin.org (optional)'),
                  ),
                ],
              ),
            ],
          ),
          _Section(
            title: 'Diagnostics',
            children: [
              Text(
                'accepted ${d.eventsAccepted} · dropped by level '
                '${d.eventsDroppedLevel} · seal failures ${d.sealFailures} · '
                'storage failures ${d.storageFailures} · uploads '
                '${d.uploadAttempts} (failed ${d.uploadFailures}) · purged '
                '${d.purgedRows}',
              ),
              const SizedBox(height: 4),
              Text('last upload: $_lastUpload'),
            ],
          ),
          _Section(
            title: 'Mock ingest server (${_ingest.received.length} envelopes)',
            children: [
              const Text(
                'Only ciphertext reaches the server. Without the project '
                'private key nobody, including this app, can read it.',
              ),
              for (final e in _ingest.received.reversed.take(5))
                Text(
                  '${e.batchId.substring(0, 8)}…  ${e.eventCount} events, '
                  '${e.ciphertextBytes} encrypted bytes',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
            ],
          ),
          _Section(
            title: 'Activity',
            children: [for (final m in _messages) Text('• $m')],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}
