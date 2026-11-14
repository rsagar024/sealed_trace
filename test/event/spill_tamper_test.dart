import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/crypto/envelope_sealer.dart';
import 'package:sealed_trace/src/crypto/public_key_parser.dart';
import 'package:sealed_trace/src/diagnostics/diagnostic_counters.dart';
import 'package:sealed_trace/src/event/page_exit_saver.dart';
import 'package:sealed_trace/src/model/sealed_envelope.dart';
import 'package:sealed_trace/src/queue/write_behind_queue.dart';
import 'package:sealed_trace/src/storage/envelope_spill.dart';

import '../helpers/envelopes.dart';
import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

final _now = DateTime.utc(2026, 6, 1, 12);

class _Rig {
  _Rig() {
    saver = PageExitSaver(
      queue: WriteBehindQueue(sink: (_) async {}, onError: (_, _) {}),
      sealer: EnvelopeSealer(
        publicKey: PublicKeyParser.parse(testPublicKeySpki),
        projectId: 'proj-a',
        clock: FakeClock(_now),
      ),
      spill: spill,
      store: (envelope) async => stored.add(envelope),
      counters: counters,
      onError: (_, _) {},
    );
  }

  final spill = MemoryEnvelopeSpill(maxChars: 1 << 30);
  final counters = DiagnosticCounters();
  final stored = <SealedEnvelope>[];
  late final PageExitSaver saver;
}

/// An encoded spill entry with [change] applied to its JSON fields.
String _tampered(void Function(Map<String, dynamic> m) change) {
  final m =
      jsonDecode(encodeSpilledEnvelope(makeEnvelope(id: 'e-1')))
          as Map<String, dynamic>;
  change(m);
  return jsonEncode(m);
}

void main() {
  group('L3: recovery keeps only this project\'s envelopes', () {
    test('another project\'s envelope is dropped and counted', () async {
      final rig = _Rig();
      rig.spill
        ..write(makeEnvelope(id: 'ours', projectId: 'proj-a'))
        ..write(makeEnvelope(id: 'theirs', projectId: 'proj-evil'));
      expect(await rig.saver.recover(), 1);
      expect(rig.stored.map((e) => e.batchId), ['ours']);
      expect(rig.counters.spillEntriesRejected, 1);
      expect(rig.spill.readAll(), isEmpty, reason: 'nothing left behind');
    });

    test('an envelope dated more than a day ahead is dropped', () async {
      final rig = _Rig();
      rig.spill
        ..write(
          makeEnvelope(
            id: 'skewed',
            projectId: 'proj-a',
            createdAt: _now.add(const Duration(hours: 23)),
          ),
        )
        ..write(
          makeEnvelope(
            id: 'future',
            projectId: 'proj-a',
            createdAt: _now.add(const Duration(days: 30)),
          ),
        );
      expect(await rig.saver.recover(), 1);
      expect(rig.stored.single.batchId, 'skewed');
      expect(rig.counters.spillEntriesRejected, 1);
    });

    test(
      'at most 200 are recovered, the newest; the rest are dropped',
      () async {
        final rig = _Rig();
        for (var i = 0; i < 250; i++) {
          rig.spill.write(
            makeEnvelope(
              id: 'e-${i.toString().padLeft(3, '0')}',
              projectId: 'proj-a',
              createdAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
            ),
          );
        }
        expect(await rig.saver.recover(), PageExitSaver.maxRecovered);
        expect(rig.stored.first.batchId, 'e-050');
        expect(rig.stored.last.batchId, 'e-249');
        expect(rig.counters.spillEntriesRejected, 50);
        expect(rig.spill.readAll(), isEmpty);
      },
    );
  });

  group('L3: the spill decoder rejects tampered entries', () {
    test('an untouched entry decodes', () {
      expect(decodeSpilledEnvelope(_tampered((_) {})).batchId, 'e-1');
    });

    final cases = <String, void Function(Map<String, dynamic>)>{
      'short IV': (m) => m['iv'] = base64Encode(List.filled(8, 1)),
      'short tag': (m) => m['tag'] = base64Encode(List.filled(4, 1)),
      'short wrapped key': (m) =>
          m['wrappedKey'] = base64Encode(List.filled(128, 1)),
      'ciphertext not matching payloadSize': (m) => m['payloadSize'] = 1,
      'zero events': (m) => m['eventCount'] = 0,
      'seqMin after seqMax': (m) {
        m['seqMin'] = 9;
        m['seqMax'] = 1;
      },
      'minTs after maxTs': (m) {
        m['minTs'] = 10;
        m['maxTs'] = 1;
      },
      'unknown level': (m) => m['topLevels'] = 'info,<script>',
      'odd batch id': (m) => m['batchId'] = '../../etc',
      'empty project': (m) => m['projectId'] = '',
      'old format v1': (m) => m['v'] = 1,
      'other algorithm': (m) => m['alg'] = 'none',
    };
    cases.forEach((name, change) {
      test(name, () {
        expect(
          () => decodeSpilledEnvelope(_tampered(change)),
          throwsA(anything),
        );
      });
    });

    test('an oversized entry is refused before parsing', () {
      expect(
        () => decodeSpilledEnvelope('{"pad":"${'x' * maxSpilledEntryChars}"}'),
        throwsFormatException,
      );
    });

    test('an entry stored under another batch\'s key is dropped', () {
      final dropped = <String>[];
      final good = encodeSpilledEnvelope(makeEnvelope(id: 'real'));
      final out = sortedSpill({'real': good, 'impostor': good}, dropped.add);
      expect(out.map((e) => e.batchId), ['real']);
      expect(dropped, ['impostor']);
    });
  });
}
