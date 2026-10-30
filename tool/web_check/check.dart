// ignore_for_file: avoid_print
// Compiled with dart2js and run in real browsers by drive.js. It checks, in a
// browser page, masking (including adversarial input timing on the browser's
// regex engine) and sealing, plus what only a browser has: IndexedDB storage,
// its quota error, persistence across a real reload, and the page lifecycle
// events.
//
//   dart compile js -O2 -o build/web_check/check.js tool/web_check/check.dart
//   node tool/web_check/drive.js chrome|edge|firefox
//
// The page reads its phase from the query string (`?phase=main`) and writes
// its result lines into `<pre id="result">`, then sets `data-done` on <body>.
// Flutter is not involved, so the lifecycle phases wire the SDK's own queue,
// sealer and IndexedDB store the way EventPipeline does (flush on hidden and
// detached), not through the SealedTrace facade.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:web/web.dart' as web;

import 'package:sealed_trace/src/config/mask_config.dart';
import 'package:sealed_trace/src/crypto/envelope_sealer.dart';
import 'package:sealed_trace/src/crypto/gcm.dart';
import 'package:sealed_trace/src/crypto/public_key_parser.dart';
import 'package:sealed_trace/src/diagnostics/diagnostic_counters.dart';
import 'package:sealed_trace/src/event/log_record.dart';
import 'package:sealed_trace/src/event/page_exit_saver.dart';
import 'package:sealed_trace/src/event/sealing_batch_handler.dart';
import 'package:sealed_trace/src/masking/masking_engine.dart';
import 'package:sealed_trace/src/model/log_level.dart';
import 'package:sealed_trace/src/model/sealed_envelope.dart';
import 'package:sealed_trace/src/platform/lifecycle_binding.dart';
import 'package:sealed_trace/src/platform/page_events_web.dart';
import 'package:sealed_trace/src/queue/write_behind_queue.dart';
import 'package:sealed_trace/src/storage/envelope_spill.dart';
import 'package:sealed_trace/src/storage/envelope_store.dart';
import 'package:sealed_trace/src/storage/indexeddb_storage_adapter.dart';
import 'package:sealed_trace/src/storage/retention_policy.dart';
import 'package:sealed_trace/src/storage/storage_adapter.dart';

import '../../test/helpers/test_keys.dart';

const String persistDb = 'web_check_persist';
const String lifecycleDb = 'web_check_lifecycle';
const String quotaDb = 'web_check_quota';

final List<String> _out = <String>[];

void emit(String line) {
  _out.add(line);
  print(line);
}

void check(String name, bool ok) => emit('${ok ? 'PASS' : 'FAIL'} $name');

void done() {
  final pre = web.document.getElementById('result');
  if (pre != null) pre.textContent = _out.join('\n');
  web.document.body?.setAttribute('data-done', '1');
}

String _hash(List<int> bytes) => base64Encode(sha256.convert(bytes).bytes);

const RetentionPolicy _bigPolicy = RetentionPolicy(
  maxEvents: 1 << 30,
  maxAgeDays: 3650,
  maxSizeBytes: 1 << 40,
  deadLetterTtl: Duration(days: 7),
);

EnvelopeSealer _sealer() => EnvelopeSealer(
  publicKey: PublicKeyParser.parse(testPublicKeySpki),
  projectId: 'project-web',
);

LogRecord _record(int seq, {String message = 'event', Object? field}) =>
    LogRecord(
      id: 'id-$seq',
      seq: seq,
      timestamp: DateTime.utc(2026, 1, 1, 10, 0, 0, seq),
      level: LogLevel.values[seq % LogLevel.values.length],
      tag: 'web',
      message: '$message $seq héllo ✓',
      error: null,
      stackTrace: null,
      metadata: field == null ? const {} : {'field': field},
      sessionId: 's',
      userId: null,
      ctx: const {'platform': 'web'},
    );

/// A pseudo-random string, so storage compression cannot hide its size.
String _noise(int length, int seed) {
  final random = Random(seed);
  const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ ';
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.writeCharCode(alphabet.codeUnitAt(random.nextInt(alphabet.length)));
  }
  return buffer.toString();
}

SealedEnvelope _randomEnvelope(String id, int ciphertextBytes, int seed) {
  final random = Random(seed);
  Uint8List bytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => random.nextInt(256)));
  final at = DateTime.utc(2026, 1, 1).add(Duration(seconds: seed));
  return SealedEnvelope(
    batchId: id,
    projectId: 'project-web',
    createdAt: at,
    eventCount: 1,
    wrappedKey: bytes(256),
    iv: bytes(12),
    tag: bytes(16),
    ciphertext: bytes(ciphertextBytes),
    seqMin: seed,
    seqMax: seed,
    minTs: at.millisecondsSinceEpoch,
    maxTs: at.millisecondsSinceEpoch,
    topLevels: 'info',
    payloadSize: ciphertextBytes,
  );
}

Future<void> main() async {
  final params = _params;
  final phase = params['phase'] ?? 'main';
  emit('PHASE $phase');
  emit('UA ${web.window.navigator.userAgent}');
  try {
    switch (phase) {
      case 'main':
        await _main();
      case 'persist-read':
        await _persistRead();
      case 'lifecycle-write':
        await _lifecycleWrite(mode: params['mode'] ?? 'spill');
        // The driver navigates away now; no `done` is reported on purpose
        // beyond the READY marker below.
        return;
      case 'lifecycle-read':
        await _lifecycleRead();
      case 'noop':
        emit('NOOP');
      case 'quota':
        await _quota(int.parse(params['mb'] ?? '1'));
      default:
        check('known phase', false);
    }
  } catch (error, stack) {
    check('phase $phase ran without an uncaught error: $error', false);
    emit('STACK ${stack.toString().split('\n').take(6).join(' | ')}');
  }
  done();
}

Future<void> _main() async {
  final engine = MaskingEngine(const MaskConfig());

  // Masking rules on this browser's regex engine.
  check(
    'email',
    engine.maskString('mail asha@example.com now') == 'mail *** now',
  );
  check('india phone', engine.maskString('+91 98765 43210') == '***');
  check('us phone', engine.maskString('(555) 123-4567') == '***');
  check('visa', engine.maskString('4111 1111 1111 1111') == '***');
  check('coords', engine.maskString('12.9716, 77.5946') == '***');
  check(
    'plain text untouched',
    engine.maskString('hello world 1.2.3') == 'hello world 1.2.3',
  );
  check(
    'url',
    engine.maskUrl('https://x.com/p?token=abc&n=1') ==
        'https://x.com/p?token=***&n=1',
  );
  check(
    'nested map key',
    jsonEncode(
          engine.maskValue({
            'a': {'password': 'x', 'ok': 1},
          }),
        ) ==
        '{"a":{"password":"***","ok":1}}',
  );

  // Adversarial inputs: long runs that would expose catastrophic backtracking.
  final inputs = <String, String>{
    'a x 100k': 'a' * 100000,
    '@ x 100k': '@' * 100000,
    'a@ x 50k': 'a@' * 50000,
    '1 x 100k': '1' * 100000,
    '"1 " x 50k': '1 ' * 50000,
    '"9876543210 " x 9k': '9876543210 ' * 9000,
    'a.b@c x 20k': 'a.b@c' * 20000,
    '"(555) " x 16k': '(555) ' * 16000,
  };
  inputs.forEach((name, input) {
    final w = Stopwatch()..start();
    engine.maskString(input);
    w.stop();
    emit('REDOS ${w.elapsedMilliseconds}ms $name');
  });

  // AES-256-GCM on deterministic inputs; drive.js recomputes them with Node.
  for (final size in const [0, 1, 15, 16, 17, 100, 4096, 100000]) {
    final key = Uint8List.fromList(
      List.generate(32, (i) => (i * 7 + 1) & 0xff),
    );
    final iv = Uint8List.fromList(
      List.generate(12, (i) => (i * 13 + 5) & 0xff),
    );
    final plain = Uint8List.fromList(
      List.generate(size, (i) => (i * 31 + (i >> 3)) & 0xff),
    );
    final (ct, tag) = AesGcm256.encrypt(key: key, iv: iv, plaintext: plain);
    emit('GCM $size ${_hash(ct)} ${base64Encode(tag)}');
  }

  // Sealing on the main thread. The queue caps a batch at 25 events and
  // 64 KB unless a single event is larger, so the largest real batches are
  // "25 events filling 64 KB" and "one event at the 128 K cap". The 25 x 128 K
  // case cannot come out of the queue; it is measured as an upper bound.
  final sealer = _sealer();
  final cases = <String, List<LogRecord>>{
    '25 small': [for (var i = 1; i <= 25; i++) _record(i)],
    '25 filling 64 KB': [
      for (var i = 1; i <= 25; i++) _record(i, field: _noise(2500, i)),
    ],
    '1 x 128 K': [_record(1, field: _noise(127000, 1))],
    '25 x 128 K (bound)': [
      for (var i = 1; i <= 25; i++) _record(i, field: _noise(127000, i)),
    ],
  };
  for (final entry in cases.entries) {
    final plaintext = jsonEncode([for (final r in entry.value) r.toJson()]);
    final w = Stopwatch()..start();
    final envelope = await sealer.seal(entry.value);
    w.stop();
    emit(
      'SEAL ${w.elapsedMilliseconds}ms ${envelope.payloadSize}B ${entry.key}',
    );
    emit(
      'ENVELOPE ${jsonEncode({'name': entry.key, 'wire': envelope.toWireJson(), 'plainHash': _hash(utf8.encode(plaintext))})}',
    );
  }

  // Masking a worst-case event on the caller's (main) thread.
  final big = {'field': _noise(127000, 9), 'email': 'asha@example.com'};
  final mw = Stopwatch()..start();
  final masked = engine.maskValue(big) as Map;
  mw.stop();
  emit('MASKMS ${mw.elapsedMilliseconds}ms 127 K-character field');
  check('worst-case event masked', masked['email'] == '***');

  // The page lifecycle source.
  final seen = <AppLifecycle>[];
  final sub = pageLifecycleEvents().listen(seen.add);
  web.window.dispatchEvent(web.Event('pagehide'));
  web.document.dispatchEvent(web.Event('visibilitychange'));
  await Future<void>.delayed(Duration.zero);
  await sub.cancel();
  final visible = web.document.visibilityState;
  check(
    'pagehide reports detached; visibilitychange while $visible '
    '${visible == 'hidden' ? 'reports hidden' : 'reports nothing'}',
    seen.isNotEmpty &&
        seen.first == AppLifecycle.detached &&
        seen.length == (visible == 'hidden' ? 2 : 1),
  );

  // Storage: write real sealed envelopes for the persist-read phase, which
  // the driver runs after a real page reload.
  final adapter = IndexedDbStorageAdapter(databaseName: persistDb);
  await adapter.deleteDatabase();
  await adapter.open();
  final store = EnvelopeStore(adapter: adapter, policy: _bigPolicy);
  final expected = <String, String>{};
  for (var i = 0; i < 3; i++) {
    final envelope = await sealer.seal([
      for (var j = 1; j <= 5; j++) _record(i * 10 + j),
    ]);
    await store.append(envelope);
    expected[envelope.batchId] = _hash(envelope.ciphertext);
  }
  await adapter.writeMeta('expected', jsonEncode(expected));
  final stats = await store.stats();
  check(
    'IndexedDB holds 3 envelopes and 15 events',
    stats.envelopes == 3 && stats.events == 15,
  );
  await adapter.close();
}

Future<void> _persistRead() async {
  final adapter = IndexedDbStorageAdapter(databaseName: persistDb);
  await adapter.open();
  final raw = await adapter.readMeta('expected');
  check('meta survived the reload', raw != null);
  final expected = (jsonDecode(raw ?? '{}') as Map).cast<String, String>();
  final rows = await adapter.fetch(expected.keys);
  check(
    'all ${expected.length} envelopes survived the reload',
    expected.isNotEmpty && rows.length == expected.length,
  );
  check(
    'ciphertext is byte-identical after the reload',
    rows.every(
      (r) => expected[r.envelope.batchId] == _hash(r.envelope.ciphertext),
    ),
  );
  for (final row in rows) {
    emit('STORED ${jsonEncode({'wire': row.envelope.toWireJson()})}');
  }
  await adapter.deleteDatabase();
}

/// Mirrors EventPipeline: queue -> sealing -> IndexedDB, and the page
/// lifecycle flushes the queue. Events are added and the 2 s timer has not
/// fired when the driver navigates away.
/// Appends a timestamped step to localStorage, which is written synchronously
/// and so survives the document being torn down.
void _trace(String step) {
  final storage = web.window.localStorage;
  final now = DateTime.now().millisecondsSinceEpoch % 100000;
  storage.setItem('trace', '${storage.getItem('trace') ?? ''} $step@$now');
}

Future<void> _lifecycleWrite({required String mode}) async {
  web.window.localStorage.removeItem('trace');
  _trace('ready');
  final adapter = IndexedDbStorageAdapter(databaseName: lifecycleDb);
  await adapter.deleteDatabase();
  await adapter.open();
  final store = EnvelopeStore(adapter: adapter, policy: _bigPolicy);
  Future<void> save(SealedEnvelope envelope) async {
    _trace('sealed');
    try {
      await store.append(envelope);
      _trace('stored');
    } catch (e) {
      _trace('store error $e');
    }
  }

  final sealer = _sealer();
  final counters = DiagnosticCounters();
  final queue = WriteBehindQueue(
    sink: SealingBatchHandler(
      sealer: sealer,
      counters: counters,
      onError: (e, _) => _trace('seal error $e'),
      envelopeSink: save,
    ).call,
    onError: (e, _) => _trace('queue error $e'),
  );
  final saver = PageExitSaver(
    queue: queue,
    sealer: sealer,
    spill: openPlatformEnvelopeSpill()!,
    store: save,
    counters: counters,
    onError: (e, _) => _trace('saver error $e'),
  );
  web.window.addEventListener(
    'pagehide',
    ((web.PageTransitionEvent e) {
      _trace('pagehide persisted=${e.persisted}');
    }).toJS,
  );
  // Same routing as EventPipeline: with a saver, hidden and detached save
  // synchronously ("spill", the SDK on the web); without one they flush
  // asynchronously ("flush", the SDK before this fix). "none" listens to
  // nothing.
  if (mode != 'none') {
    pageLifecycleEvents().listen((state) {
      if (state == AppLifecycle.hidden || state == AppLifecycle.detached) {
        _trace(state.name);
        if (mode == 'spill') {
          saver.saveNow();
          _trace('spilled');
        } else {
          unawaited(queue.flush());
        }
      }
    });
  }
  for (var i = 1; i <= 5; i++) {
    queue.add(_record(i));
  }
  emit('READY');
  done();
}

/// The next start: count what reached IndexedDB by itself, then let
/// [PageExitSaver.recover] move whatever is in the spill, as init does.
Future<void> _lifecycleRead() async {
  final adapter = IndexedDbStorageAdapter(databaseName: lifecycleDb);
  await adapter.open();
  final store = EnvelopeStore(adapter: adapter, policy: _bigPolicy);
  final spill = openPlatformEnvelopeSpill()!;
  emit('TRACE ${web.window.localStorage.getItem('trace') ?? '(none)'}');
  web.window.localStorage.removeItem('trace');
  final direct = await adapter.listIndex();
  final spilled = spill.readAll().length;
  final saver = PageExitSaver(
    queue: WriteBehindQueue(sink: (_) async {}, onError: (_, _) {}),
    sealer: _sealer(),
    spill: spill,
    store: store.append,
    counters: DiagnosticCounters(),
    onError: (e, _) => emit('TRACE recover error $e'),
  );
  final moved = await saver.recover();
  final rows = await adapter.listIndex();
  final events = rows.fold<int>(0, (sum, r) => sum + r.eventCount);
  emit(
    'LIFECYCLE ${rows.length} envelopes, $events events '
    '(${direct.length} in IndexedDB before recovery, $spilled spilled, '
    '$moved moved, ${spill.readAll().length} left in the spill)',
  );
  await adapter.deleteDatabase();
}

/// Fills IndexedDB until the browser refuses, then checks the emergency
/// purge in EnvelopeStore.append and that a write that can never fit fails.
Future<String> _estimate() async {
  final e = await web.window.navigator.storage.estimate().toDart;
  return 'usage ${e.usage} quota ${e.quota}';
}

Future<void> _quota(int megabytes) async {
  emit('QUOTA estimate at start: ${await _estimate()}');
  final adapter = IndexedDbStorageAdapter(databaseName: quotaDb);
  await adapter.deleteDatabase();
  await adapter.open();
  final store = EnvelopeStore(adapter: adapter, policy: _bigPolicy);
  final size = megabytes * 1024 * 1024;

  Object? failure;
  var inserted = 0;
  for (var i = 0; i < 400; i++) {
    try {
      await adapter.insertEnvelope(
        EnvelopeRow.pending(_randomEnvelope('q-${1000 + i}', size, i)),
      );
      inserted++;
    } catch (error) {
      failure = error;
      break;
    }
  }
  emit('QUOTA estimate after filling: ${await _estimate()}');
  emit(
    'QUOTA filled $inserted envelopes of $megabytes MB before: '
    '${failure is StorageFullException ? 'StorageFullException(${failure.cause})' : failure}',
  );
  check(
    'the quota error maps to StorageFullException',
    failure is StorageFullException,
  );
  if (failure is! StorageFullException) {
    await adapter.deleteDatabase();
    return;
  }

  final before = (await adapter.listIndex()).length;
  var appended = false;
  try {
    await store.append(_randomEnvelope('q-9000', size, 9000));
    appended = true;
  } catch (error) {
    emit('QUOTA append after purge failed: $error');
  }
  final after = await adapter.listIndex();
  emit('QUOTA rows before $before, after append ${after.length}');
  check(
    'append purges the oldest rows and then stores the new envelope',
    appended &&
        after.any((r) => r.batchId == 'q-9000') &&
        after.length < before + 1 &&
        !after.any((r) => r.batchId == 'q-1000'),
  );

  // Larger than the whole quota: purge once, retry once, then fail.
  Object? second;
  try {
    await store.append(_randomEnvelope('q-9999', size * (inserted + 2), 9999));
  } catch (error) {
    second = error;
  }
  check(
    'a write that can never fit is reported as StorageFullException',
    second is StorageFullException,
  );
  check(
    'the database is still usable afterwards',
    (await adapter.listIndex()).isNotEmpty,
  );
  await adapter.deleteDatabase();
}

Map<String, String> get _params =>
    Uri.parse(web.window.location.href).queryParameters;
