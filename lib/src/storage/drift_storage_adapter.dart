import 'package:drift/drift.dart';

import '../model/sealed_envelope.dart';
import 'database.dart';
import 'storage_adapter.dart';

/// A [StorageAdapter] backed by SQLite through drift.
///
/// Used on `dart:io` platforms. The schema is the one in `database.dart`.
class DriftStorageAdapter implements StorageAdapter {
  /// Creates an adapter over a drift [executor].
  DriftStorageAdapter(QueryExecutor executor) : _db = SealedDatabase(executor);

  final SealedDatabase _db;

  // SQLite caps bound variables per statement (999 on older builds).
  static const int _chunk = 400;

  @override
  Future<void> open() async {
    // Drift opens lazily; force it so a corrupt file fails here, not later.
    await _db.customSelect('SELECT 1').get();
  }

  @override
  Future<void> insertEnvelope(EnvelopeRow row) async {
    final e = row.envelope;
    try {
      await _db
          .into(_db.sealedEnvelopes)
          .insert(
            SealedEnvelopesCompanion.insert(
              batchId: e.batchId,
              projectId: e.projectId,
              createdAt: e.createdAt.millisecondsSinceEpoch,
              eventCount: e.eventCount,
              payloadSize: e.payloadSize,
              wrappedKey: e.wrappedKey,
              iv: e.iv,
              tag: e.tag,
              ciphertext: e.ciphertext,
              uploadState: Value(row.uploadState),
              attempts: Value(row.attempts),
              lastAttemptAt: Value(row.lastAttemptAt),
              seqMin: e.seqMin,
              seqMax: e.seqMax,
              minTs: e.minTs,
              maxTs: e.maxTs,
              topLevels: e.topLevels,
              uploadedAt: Value(row.uploadedAt),
            ),
          );
    } catch (error) {
      if (_isFull(error)) throw StorageFullException(error);
      rethrow;
    }
  }

  @override
  Future<List<EnvelopeIndexRow>> listIndex() async {
    final result = await _db
        .customSelect(
          'SELECT batch_id, created_at, event_count, upload_state, attempts, '
          'last_attempt_at, uploaded_at, '
          'length(wrapped_key) + length(iv) + length(tag) + length(ciphertext) '
          'AS size_bytes '
          'FROM sealed_envelopes ORDER BY created_at ASC, batch_id ASC',
          readsFrom: {_db.sealedEnvelopes},
        )
        .get();
    return <EnvelopeIndexRow>[
      for (final row in result)
        EnvelopeIndexRow(
          batchId: row.read<String>('batch_id'),
          createdAt: row.read<int>('created_at'),
          eventCount: row.read<int>('event_count'),
          sizeBytes: row.read<int>('size_bytes'),
          uploadState: row.read<int>('upload_state'),
          attempts: row.read<int>('attempts'),
          lastAttemptAt: row.read<int?>('last_attempt_at'),
          uploadedAt: row.read<int?>('uploaded_at'),
        ),
    ];
  }

  @override
  Future<List<EnvelopeRow>> fetch(Iterable<String> batchIds) async {
    final rows = <EnvelopeRow>[];
    for (final ids in _chunks(batchIds)) {
      final records = await (_db.select(
        _db.sealedEnvelopes,
      )..where((t) => t.batchId.isIn(ids))).get();
      rows.addAll(records.map(_toRow));
    }
    rows.sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0
          ? byTime
          : a.envelope.batchId.compareTo(b.envelope.batchId);
    });
    return rows;
  }

  @override
  Future<void> deleteBatches(Iterable<String> batchIds) async {
    for (final ids in _chunks(batchIds)) {
      await (_db.delete(
        _db.sealedEnvelopes,
      )..where((t) => t.batchId.isIn(ids))).go();
    }
  }

  @override
  Future<void> patch(
    Iterable<String> batchIds, {
    int attemptsDelta = 0,
    int? lastAttemptAt,
    int? uploadState,
    int? uploadedAt,
  }) async {
    for (final ids in _chunks(batchIds)) {
      final marks = List<String>.filled(ids.length, '?').join(',');
      await _db.customUpdate(
        'UPDATE sealed_envelopes SET '
        'attempts = attempts + ?, '
        'last_attempt_at = COALESCE(?, last_attempt_at), '
        'upload_state = COALESCE(?, upload_state), '
        'uploaded_at = COALESCE(?, uploaded_at) '
        'WHERE batch_id IN ($marks)',
        variables: <Variable<Object>>[
          Variable<int>(attemptsDelta),
          Variable<int>(lastAttemptAt),
          Variable<int>(uploadState),
          Variable<int>(uploadedAt),
          for (final id in ids) Variable<String>(id),
        ],
        updates: {_db.sealedEnvelopes},
      );
    }
  }

  @override
  Future<void> clearAll() async {
    await _db.delete(_db.sealedEnvelopes).go();
  }

  @override
  Future<String?> readMeta(String key) async {
    final record = await (_db.select(
      _db.sealedMeta,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return record?.value;
  }

  @override
  Future<void> writeMeta(String key, String value) async {
    await _db
        .into(_db.sealedMeta)
        .insertOnConflictUpdate(
          SealedMetaCompanion.insert(key: key, value: value),
        );
  }

  @override
  Future<void> close() => _db.close();

  /// Runs a raw statement. Used by tests to inspect pragmas.
  Future<List<QueryRow>> rawSelect(String sql) => _db.customSelect(sql).get();

  Iterable<List<String>> _chunks(Iterable<String> ids) sync* {
    final all = ids.toList();
    for (var i = 0; i < all.length; i += _chunk) {
      yield all.sublist(i, i + _chunk > all.length ? all.length : i + _chunk);
    }
  }

  static EnvelopeRow _toRow(EnvelopeRecord r) => EnvelopeRow(
    envelope: SealedEnvelope(
      batchId: r.batchId,
      projectId: r.projectId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt, isUtc: true),
      eventCount: r.eventCount,
      wrappedKey: r.wrappedKey,
      iv: r.iv,
      tag: r.tag,
      ciphertext: r.ciphertext,
      seqMin: r.seqMin,
      seqMax: r.seqMax,
      minTs: r.minTs,
      maxTs: r.maxTs,
      topLevels: r.topLevels,
      payloadSize: r.payloadSize,
    ),
    uploadState: r.uploadState,
    attempts: r.attempts,
    lastAttemptAt: r.lastAttemptAt,
    uploadedAt: r.uploadedAt,
  );

  static bool _isFull(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('database or disk is full') ||
        text.contains('sqlite_full') ||
        text.contains('disk full');
  }
}
