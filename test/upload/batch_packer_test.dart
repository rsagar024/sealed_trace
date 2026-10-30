import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/storage/storage_adapter.dart';
import 'package:sealed_trace/src/upload/batch_packer.dart';

import '../helpers/envelopes.dart';

EnvelopeRow _row(String id, {int ciphertext = 64}) =>
    EnvelopeRow.pending(makeEnvelope(id: id, ciphertextLength: ciphertext));

List<EnvelopeRow> _rows(int count, {int ciphertext = 64}) => [
  for (var i = 0; i < count; i++)
    _row('b-${i.toString().padLeft(3, '0')}', ciphertext: ciphertext),
];

/// The real request body for [rows].
String _body(List<EnvelopeRow> rows) => jsonEncode({
  'envelopes': [for (final r in rows) r.envelope.toWireJson()],
});

void main() {
  test('the limits come from the contract', () {
    expect(BatchPacker.maxEnvelopesPerRequest, 50);
    expect(BatchPacker.maxRequestBytes, 2000000);
  });

  test('bodyBytes equals the length of the real request body', () {
    for (final count in [0, 1, 2, 7, 50]) {
      final rows = _rows(count);
      final expected = count == 0
          ? utf8.encode(jsonEncode({'envelopes': <Object>[]})).length
          : utf8.encode(_body(rows)).length;
      expect(
        BatchPacker.bodyBytes(rows.map((r) => r.envelope)),
        expected,
        reason: '$count envelopes',
      );
    }
  });

  test('at most 50 envelopes per request, oldest first', () {
    final rows = _rows(120);
    final packed = BatchPacker.pack(rows);
    expect(packed.rows, hasLength(50));
    expect(
      packed.rows.map((r) => r.envelope.batchId),
      rows.take(50).map((r) => r.envelope.batchId),
    );
    expect(packed.oversized, isEmpty);
  });

  test('a smaller maxEnvelopes is honored, and larger than 50 is clamped', () {
    expect(BatchPacker.pack(_rows(30), maxEnvelopes: 10).rows, hasLength(10));
    expect(BatchPacker.pack(_rows(80), maxEnvelopes: 500).rows, hasLength(50));
    expect(BatchPacker.pack(_rows(5), maxEnvelopes: 0).rows, hasLength(1));
  });

  test('fewer rows than the limit are all taken', () {
    expect(BatchPacker.pack(_rows(3)).rows, hasLength(3));
    expect(BatchPacker.pack(const []).rows, isEmpty);
  });

  group('byte limit', () {
    test('exactly at the limit fits; one byte less does not', () {
      final rows = _rows(4, ciphertext: 300);
      final exact = BatchPacker.bodyBytes(rows.map((r) => r.envelope));

      final fits = BatchPacker.pack(rows, maxBytes: exact);
      expect(fits.rows, hasLength(4));

      final tooSmall = BatchPacker.pack(rows, maxBytes: exact - 1);
      expect(tooSmall.rows, hasLength(3));
      expect(
        BatchPacker.bodyBytes(tooSmall.rows.map((r) => r.envelope)),
        lessThanOrEqualTo(exact - 1),
      );
    });

    test('the default limit stops a large backlog before 2,000,000 bytes', () {
      // ~100 KB of base64 per envelope.
      final rows = _rows(40, ciphertext: 75000);
      final packed = BatchPacker.pack(rows);
      expect(packed.rows.length, lessThan(40));
      expect(packed.rows, isNotEmpty);
      expect(
        utf8.encode(_body(packed.rows)).length,
        lessThanOrEqualTo(BatchPacker.maxRequestBytes),
      );
    });

    test('an envelope too big for any request is reported, not packed', () {
      final rows = [
        _row('small-1'),
        _row('huge', ciphertext: 1600000), // ~2.1 MB once base64-encoded
        _row('small-2'),
      ];
      final packed = BatchPacker.pack(rows);
      expect(packed.oversized.map((r) => r.envelope.batchId), ['huge']);
      expect(packed.rows.map((r) => r.envelope.batchId), [
        'small-1',
        'small-2',
      ]);
    });

    test('only oversized rows gives an empty batch', () {
      final packed = BatchPacker.pack([_row('huge', ciphertext: 1600000)]);
      expect(packed.rows, isEmpty);
      expect(packed.oversized, hasLength(1));
    });

    test('a row that exactly fills the request leaves the next one out', () {
      final big = _row('big', ciphertext: 3000);
      final next = _row('next');
      final limit = BatchPacker.bodyBytes([big.envelope]);
      final packed = BatchPacker.pack([big, next], maxBytes: limit);
      expect(packed.rows.map((r) => r.envelope.batchId), ['big']);
      expect(packed.oversized, isEmpty);
    });
  });

  test(
    'property: whatever the sizes, a packed request never exceeds the limits',
    () {
      final random = Random(2026);
      for (var round = 0; round < 40; round++) {
        final count = 1 + random.nextInt(90);
        final rows = [
          for (var i = 0; i < count; i++)
            _row('p-$round-$i', ciphertext: 1 + random.nextInt(120000)),
        ];
        final limitBytes = 50000 + random.nextInt(2000000);
        final packed = BatchPacker.pack(rows, maxBytes: limitBytes);

        expect(packed.rows.length, lessThanOrEqualTo(50));
        if (packed.rows.isNotEmpty) {
          expect(
            utf8.encode(_body(packed.rows)).length,
            lessThanOrEqualTo(limitBytes),
            reason: 'round $round',
          );
        }
        // Order is preserved: packed rows are a subsequence from the front,
        // skipping only oversized ones.
        final ids = rows.map((r) => r.envelope.batchId).toList();
        var cursor = 0;
        for (final row in packed.rows) {
          final at = ids.indexOf(row.envelope.batchId, cursor);
          expect(
            at,
            greaterThanOrEqualTo(cursor),
            reason: 'order, round $round',
          );
          cursor = at + 1;
        }
        // Nothing is both packed and oversized.
        final both = packed.rows
            .map((r) => r.envelope.batchId)
            .toSet()
            .intersection(
              packed.oversized.map((r) => r.envelope.batchId).toSet(),
            );
        expect(both, isEmpty);
      }
    },
  );

  group('halve (the response to HTTP 413)', () {
    test('takes the first half, at least one', () {
      expect(BatchPacker.halve(_rows(8)), hasLength(4));
      expect(BatchPacker.halve(_rows(7)), hasLength(3));
      expect(BatchPacker.halve(_rows(2)), hasLength(1));
      expect(BatchPacker.halve(_rows(1)), hasLength(1));
    });

    test('keeps the oldest rows', () {
      final rows = _rows(6);
      expect(
        BatchPacker.halve(rows).map((r) => r.envelope.batchId),
        rows.take(3).map((r) => r.envelope.batchId),
      );
    });
  });
}
