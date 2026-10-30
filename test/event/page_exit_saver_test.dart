import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/crypto/crypto_backend.dart';
import 'package:sealed_trace/src/crypto/envelope_sealer.dart';
import 'package:sealed_trace/src/crypto/public_key_parser.dart';
import 'package:sealed_trace/src/diagnostics/diagnostic_counters.dart';
import 'package:sealed_trace/src/event/page_exit_saver.dart';
import 'package:sealed_trace/src/model/sealed_envelope.dart';
import 'package:sealed_trace/src/queue/write_behind_queue.dart';
import 'package:sealed_trace/src/storage/envelope_spill.dart';

import '../helpers/envelope_opener.dart';
import '../helpers/envelopes.dart';
import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

class _Rig {
  _Rig({EnvelopeSpill? spill, EnvelopeSealer? sealer, this.failStore = false})
    : spill = spill ?? MemoryEnvelopeSpill(),
      sealer =
          sealer ??
          EnvelopeSealer(
            publicKey: PublicKeyParser.parse(testPublicKeySpki),
            projectId: 'p',
          ) {
    saver = PageExitSaver(
      queue: queue,
      sealer: this.sealer,
      spill: this.spill,
      store: (envelope) async {
        if (failStore) throw StateError('store failed');
        stored.add(envelope);
      },
      counters: counters,
      onError: (error, _) => errors.add(error),
    );
  }

  final EnvelopeSpill spill;
  bool failStore;
  final EnvelopeSealer sealer;
  final queue = WriteBehindQueue(sink: (_) async {}, onError: (_, _) {});
  final counters = DiagnosticCounters();
  final stored = <SealedEnvelope>[];
  final errors = <Object>[];
  late final PageExitSaver saver;
}

/// A backend whose synchronous AES always fails.
class _BrokenBackend extends DefaultCryptoBackend {
  @override
  AesGcmResult aesGcmEncryptSync({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List plaintext,
  }) => throw StateError('aes failed');
}

/// A spill whose writes always fail, like a full localStorage.
class _FullSpill extends MemoryEnvelopeSpill {
  @override
  bool write(SealedEnvelope envelope) => false;
}

void main() {
  test(
    'saveNow seals and spills synchronously, then moves to storage',
    () async {
      final rig = _Rig();
      for (var i = 0; i < 3; i++) {
        rig.queue.add(makeRecord(message: 'secret-$i'));
      }

      rig.saver.saveNow();
      // Before any await: the queue is empty and the envelope is in the spill.
      expect(rig.queue.length, 0);
      final spilled = rig.spill.readAll();
      expect(spilled, hasLength(1));
      expect(spilled.single.eventCount, 3);
      final plain = await openEnvelope(spilled.single);
      expect((jsonDecode(plain) as List).length, 3);

      await pumpEventQueue();
      expect(rig.stored.map((e) => e.batchId), [spilled.single.batchId]);
      expect(rig.spill.readAll(), isEmpty);
    },
  );

  test('the spill holds ciphertext only, never the message text', () {
    final rig = _Rig();
    rig.queue.add(makeRecord(message: 'plaintext-marker'));
    rig.saver.saveNow();
    final encoded = encodeSpilledEnvelope(rig.spill.readAll().single);
    expect(encoded, isNot(contains('plaintext-marker')));
  });

  test('a long queue is split into sink-sized batches', () {
    final rig = _Rig();
    for (var i = 0; i < 60; i++) {
      rig.queue.add(makeRecord());
    }
    rig.saver.saveNow();
    expect(rig.spill.readAll().map((e) => e.eventCount), [25, 25, 10]);
  });

  test(
    'when the spill is full the envelope goes straight to storage',
    () async {
      final rig = _Rig(spill: _FullSpill());
      rig.queue.add(makeRecord());
      rig.saver.saveNow();
      await pumpEventQueue();
      expect(rig.stored, hasLength(1));
    },
  );

  test(
    'a failed move keeps the envelope in the spill for the next start',
    () async {
      final rig = _Rig(failStore: true);
      rig.queue.add(makeRecord());
      rig.saver.saveNow();
      await pumpEventQueue();
      expect(rig.spill.readAll(), hasLength(1));
      expect(rig.errors.single, isStateError);

      rig.failStore = false;
      expect(await rig.saver.recover(), 1);
      expect(rig.stored, hasLength(1));
      expect(rig.spill.readAll(), isEmpty);
    },
  );

  test(
    'after the spill fills, later batches are sealed and stored later',
    () async {
      // Room for one 25-event envelope only, measured from a real one.
      final probe = EnvelopeSealer(
        publicKey: PublicKeyParser.parse(testPublicKeySpki),
        projectId: 'p',
      ).sealSync([for (var i = 0; i < 25; i++) makeRecord()]);
      final one = encodeSpilledEnvelope(probe).length;
      final rig = _Rig(spill: MemoryEnvelopeSpill(maxChars: one + one ~/ 2));
      for (var i = 0; i < 75; i++) {
        rig.queue.add(makeRecord());
      }
      rig.saver.saveNow();
      expect(rig.queue.length, 0);
      expect(rig.spill.readAll(), hasLength(1));
      // The refused envelope is stored at once; the third batch is sealed on
      // a later event-loop turn, not inside the page event.
      await pumpEventQueue();
      expect(rig.stored, hasLength(3));
      expect(rig.spill.readAll(), isEmpty);
      final opened = [for (final e in rig.stored) await openEnvelope(e)];
      expect(opened.map((p) => (jsonDecode(p) as List).length), [25, 25, 25]);
    },
  );

  test('no spill exists outside the browser', () {
    expect(openPlatformEnvelopeSpill(), isNull);
  });

  test('recover moves spilled envelopes oldest first', () async {
    final rig = _Rig();
    final newer = makeEnvelope(id: 'b', createdAt: DateTime.utc(2026, 1, 2));
    final older = makeEnvelope(id: 'a', createdAt: DateTime.utc(2026, 1, 1));
    rig.spill.write(newer);
    rig.spill.write(older);
    expect(await rig.saver.recover(), 2);
    expect(rig.stored.map((e) => e.batchId), ['a', 'b']);
  });

  test('clear empties the spill', () {
    final rig = _Rig();
    rig.spill.write(makeEnvelope(id: 'x'));
    rig.saver.clear();
    expect(rig.spill.readAll(), isEmpty);
  });

  test('a batch that cannot be sealed is counted and never spilled', () {
    final rig = _Rig(
      sealer: EnvelopeSealer(
        publicKey: PublicKeyParser.parse(testPublicKeySpki),
        projectId: 'p',
        backend: _BrokenBackend(),
      ),
    );
    rig.queue.add(makeRecord(message: 'plaintext-marker'));
    rig.saver.saveNow();
    expect(rig.counters.sealFailures, 1);
    expect(rig.spill.readAll(), isEmpty);
    expect(rig.stored, isEmpty);
    expect(rig.errors, hasLength(1));
  });

  group('spill codec', () {
    test('round-trips every field', () {
      final e = makeEnvelope(id: 'z', eventCount: 4, seqMin: 3, seqMax: 9);
      final back = decodeSpilledEnvelope(encodeSpilledEnvelope(e));
      expect(back.batchId, e.batchId);
      expect(back.projectId, e.projectId);
      expect(back.createdAt, e.createdAt);
      expect(back.eventCount, 4);
      expect(back.wrappedKey, e.wrappedKey);
      expect(back.iv, e.iv);
      expect(back.tag, e.tag);
      expect(back.ciphertext, e.ciphertext);
      expect([back.seqMin, back.seqMax], [3, 9]);
      expect([back.minTs, back.maxTs], [e.minTs, e.maxTs]);
      expect(back.topLevels, e.topLevels);
      expect(back.payloadSize, e.payloadSize);
    });

    test('an unreadable entry is dropped, the rest is kept', () {
      final dropped = <String>[];
      final good = makeEnvelope(id: 'good');
      final out = sortedSpill({
        'good': encodeSpilledEnvelope(good),
        'bad': '{"v":2}',
        'junk': 'not json',
      }, dropped.add);
      expect(out.map((e) => e.batchId), ['good']);
      expect(dropped, unorderedEquals(['bad', 'junk']));
    });

    test('the memory spill refuses writes past its capacity', () {
      final spill = MemoryEnvelopeSpill(maxChars: 2000);
      expect(spill.write(makeEnvelope(id: 'a')), isTrue);
      expect(
        spill.write(makeEnvelope(id: 'b', ciphertextLength: 4000)),
        isFalse,
      );
      expect(spill.readAll().map((e) => e.batchId), ['a']);
    });
  });

  test('sealSync produces an envelope that opens like seal', () async {
    final sealer = EnvelopeSealer(
      publicKey: PublicKeyParser.parse(testPublicKeySpki),
      projectId: 'p',
    );
    final records = [makeRecord(message: 'one'), makeRecord(message: 'two')];
    final sync = sealer.sealSync(records);
    final async = await sealer.seal(records);
    expect(await openEnvelope(sync), await openEnvelope(async));
    expect(sync.eventCount, 2);
    expect(sync.payloadSize, async.payloadSize);
    expect(sync.topLevels, async.topLevels);
    expect(() => sealer.sealSync(const []), throwsArgumentError);
  });

  test('takeBatches empties the queue and cancels its timer', () {
    final queue = WriteBehindQueue(sink: (_) async {}, onError: (_, _) {});
    queue.add(makeRecord());
    expect(queue.hasPendingTimer, isTrue);
    final batches = queue.takeBatches();
    expect(batches.single, hasLength(1));
    expect(queue.hasPendingTimer, isFalse);
    expect(queue.takeBatches(), isEmpty);
    unawaited(queue.dispose());
  });
}
