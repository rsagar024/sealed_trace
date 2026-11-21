import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/event/event_builder.dart';
import 'package:sealed_trace/src/event/log_record.dart';
import 'package:sealed_trace/src/event/sequence_counter.dart';
import 'package:sealed_trace/src/platform/clock.dart';
import 'package:sealed_trace/src/platform/network_state.dart';

import '../helpers/fakes.dart';

class _Wifi implements NetworkStateProvider {
  @override
  String current() => 'wifi';
}

EventBuilder _builder({
  SealedTraceEnv env = SealedTraceEnv.prod,
  NetworkStateProvider? network,
  String Function()? newId,
}) {
  return EventBuilder(
    sequence: SequenceCounter(InMemorySequenceStore(), highWater: 0),
    sessionId: 'session-1',
    device: testDevice,
    env: env,
    network: network ?? const UnknownNetworkState(),
    clock: FakeClock(DateTime.utc(2026, 1, 1, 10)),
    newId: newId ?? () => 'id-fixed',
  );
}

void main() {
  test('toJson matches the section 5 schema exactly', () {
    final record = _builder().build(
      level: LogLevel.error,
      tag: 'auth',
      message: 'login failed',
      error: StateError('bad'),
      stack: StackTrace.fromString('#0 main'),
      meta: {'attempt': 2},
      userId: 'u-1',
    );
    final json = record.toJson();

    expect(json.keys.toList(), [
      'id',
      'seq',
      'ts',
      'level',
      'tag',
      'message',
      'error',
      'stackTrace',
      'metadata',
      'sessionId',
      'userId',
      'ctx',
    ]);
    expect(json['id'], 'id-fixed');
    expect(json['seq'], 1);
    expect(json['ts'], '2026-01-01T10:00:00.000Z');
    expect(json['level'], 'error');
    expect(json['tag'], 'auth');
    expect(json['message'], 'login failed');
    expect(json['error'], 'Bad state: bad');
    expect(json['stackTrace'], '#0 main');
    expect(json['metadata'], {'attempt': 2});
    expect(json['sessionId'], 'session-1');
    expect(json['userId'], 'u-1');
    expect(json['ctx'], {
      'appVersion': '1.2.3',
      'buildNumber': '45',
      'platform': 'android',
      'os': 'Android 14',
      'locale': 'en_IN',
      'env': 'prod',
      'network': 'unknown',
    });
    expect(() => jsonEncode(json), returnsNormally);
  });

  test('null error, stack and user serialize as null', () {
    final json = _builder()
        .build(level: LogLevel.info, tag: 't', message: 'm')
        .toJson();
    expect(json['error'], isNull);
    expect(json['stackTrace'], isNull);
    expect(json['userId'], isNull);
    expect(json['metadata'], isEmpty);
  });

  test('timestamps are truncated to milliseconds and UTC', () {
    final record = _builder().build(
      level: LogLevel.info,
      tag: 't',
      message: 'm',
      timestamp: DateTime.parse('2026-03-04T05:06:07.123456+05:30'),
    );
    expect(record.timestamp.isUtc, isTrue);
    // 05:06:07 at +05:30 is 23:36:07 UTC on the previous day.
    expect(record.toJson()['ts'], '2026-03-03T23:36:07.123Z');
  });

  test('a LogRecord built with a local time is stored and sent as UTC', () {
    final local = DateTime(2026, 3, 4, 5, 6, 7, 123);
    final record = LogRecord(
      id: 'id',
      seq: 1,
      timestamp: local,
      level: LogLevel.info,
      tag: 't',
      message: 'm',
      error: null,
      stackTrace: null,
      metadata: const <String, dynamic>{},
      sessionId: 's',
      userId: null,
      ctx: const <String, dynamic>{},
    );
    expect(record.timestamp.isUtc, isTrue);
    expect(record.timestamp.isAtSameMomentAs(local), isTrue);
    final ts = record.toJson()['ts'] as String;
    expect(ts, endsWith('Z'));
    expect(DateTime.parse(ts).isAtSameMomentAs(local), isTrue);
  });

  test('SystemClock returns UTC', () {
    expect(const SystemClock().now().isUtc, isTrue);
  });

  test('seq increases by one per record', () {
    final b = _builder();
    final seqs = [
      for (var i = 0; i < 250; i++)
        b.build(level: LogLevel.info, tag: 't', message: 'm').seq,
    ];
    expect(seqs, List.generate(250, (i) => i + 1));
  });

  test('ids come from the generator', () {
    var n = 0;
    final b = _builder(newId: () => 'id-${n++}');
    expect(b.build(level: LogLevel.info, tag: 't', message: 'm').id, 'id-0');
    expect(b.build(level: LogLevel.info, tag: 't', message: 'm').id, 'id-1');
  });

  test('default ids are uuid v4', () {
    final b = EventBuilder(
      sequence: SequenceCounter(InMemorySequenceStore(), highWater: 0),
      sessionId: 's',
      device: testDevice,
      env: SealedTraceEnv.dev,
    );
    final id = b.build(level: LogLevel.info, tag: 't', message: 'm').id;
    expect(
      id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('core context wins over caller context; userName is added', () {
    final record = _builder(env: SealedTraceEnv.staging).build(
      level: LogLevel.info,
      tag: 't',
      message: 'm',
      userName: 'Asha',
      extraContext: {'env': 'hacked', 'feature': 'beta'},
    );
    expect(record.ctx['env'], 'staging');
    expect(record.ctx['feature'], 'beta');
    expect(record.ctx['userName'], 'Asha');
  });

  test('userDisplayName comes only from the parameter', () {
    final builder = _builder();
    final fromSetContext = builder.build(
      level: LogLevel.info,
      tag: 't',
      message: 'm',
      extraContext: {'userDisplayName': 'Spoof', 'feature': 'beta'},
    );
    expect(fromSetContext.ctx.containsKey('userDisplayName'), isFalse);
    expect(fromSetContext.ctx['feature'], 'beta');

    final fromSetUser = builder.build(
      level: LogLevel.info,
      tag: 't',
      message: 'm',
      userName: 'Asha',
      userDisplayName: 'Asha',
      extraContext: {'userDisplayName': 'Spoof'},
    );
    expect(fromSetUser.ctx['userDisplayName'], 'Asha');
  });

  group('normalizeUserDisplayName', () {
    test('trims and drops blank names', () {
      expect(normalizeUserDisplayName('  Demo User  '), 'Demo User');
      expect(normalizeUserDisplayName(null), isNull);
      expect(normalizeUserDisplayName(''), isNull);
      expect(normalizeUserDisplayName(' \t\n '), isNull);
    });

    test('cuts to 256 code units', () {
      expect(normalizeUserDisplayName('a' * 300), 'a' * 256);
      expect(normalizeUserDisplayName('a' * 256), 'a' * 256);
    });

    test('never splits a surrogate pair at the cut', () {
      final name = '${'a' * 255}\u{1F600}tail';
      expect(normalizeUserDisplayName(name), 'a' * 255);
    });
  });

  test('custom env names are reported as is', () {
    final record = _builder(
      env: const SealedTraceEnv('qa'),
    ).build(level: LogLevel.info, tag: 't', message: 'm');
    expect(record.ctx['env'], 'qa');
  });

  test('network comes from the provider on every event', () {
    final record = _builder(
      network: _Wifi(),
    ).build(level: LogLevel.info, tag: 't', message: 'm');
    expect(record.ctx['network'], 'wifi');
  });

  test('builtCount counts builds', () {
    final b = _builder();
    b.build(level: LogLevel.info, tag: 't', message: 'm');
    b.build(level: LogLevel.info, tag: 't', message: 'm');
    expect(b.builtCount, 2);
  });

  test('oversized fields are shortened with a suffix', () {
    final huge = 'x' * (200 * 1024);
    final record = _builder().build(
      level: LogLevel.info,
      tag: 't',
      message: huge,
      error: huge,
      stack: StackTrace.fromString(huge),
    );
    expect(record.approxBytes, lessThanOrEqualTo(EventBuilder.maxEventChars));
    expect(record.message, endsWith('…[truncated]'));
    expect(record.error, endsWith('…[truncated]'));
    expect(record.stackTrace, endsWith('…[truncated]'));
  });

  test('metadata is dropped only when shortening is not enough', () {
    final record = _builder().build(
      level: LogLevel.info,
      tag: 't',
      message: 'm',
      meta: {for (var i = 0; i < 20; i++) 'k$i': 'y' * 20000},
    );
    expect(record.metadata['_truncated'], isTrue);
    expect(record.approxBytes, lessThanOrEqualTo(EventBuilder.maxEventChars));
  });

  test('a network-sized event with two 20k bodies is kept whole', () {
    final record = _builder().build(
      level: LogLevel.debug,
      tag: 'network',
      message: 'GET /x -> 200 in 5ms',
      meta: {'requestBody': 'a' * 20000, 'responseBody': 'b' * 20000},
    );
    expect(record.metadata.containsKey('_truncated'), isFalse);
    expect((record.metadata['requestBody'] as String).length, 20000);
  });
}
