import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../model/sealed_envelope.dart';
import 'storage_adapter.dart';

/// A [StorageAdapter] backed by the browser's IndexedDB.
///
/// Two object stores keep the small index records apart from the encrypted
/// blobs, so scanning for retention never loads ciphertext. A third store holds
/// bookkeeping values.
class IndexedDbStorageAdapter implements StorageAdapter {
  /// Creates an adapter for the database called [databaseName].
  IndexedDbStorageAdapter({this.databaseName = 'sealed_trace'});

  /// IndexedDB database name.
  final String databaseName;

  static const String _index = 'index';
  static const String _blobs = 'blobs';
  static const String _meta = 'meta';

  web.IDBDatabase? _db;

  web.IDBDatabase get _open {
    final db = _db;
    if (db == null) throw StateError('IndexedDB adapter is not open');
    return db;
  }

  @override
  Future<void> open() async {
    final request = web.window.indexedDB.open(databaseName, 1);
    request.onupgradeneeded = ((web.Event _) {
      final db = request.result! as web.IDBDatabase;
      db.createObjectStore(
        _index,
        web.IDBObjectStoreParameters(keyPath: 'batchId'.toJS),
      );
      db.createObjectStore(
        _blobs,
        web.IDBObjectStoreParameters(keyPath: 'batchId'.toJS),
      );
      db.createObjectStore(
        _meta,
        web.IDBObjectStoreParameters(keyPath: 'key'.toJS),
      );
    }).toJS;
    _db = (await _await(request))! as web.IDBDatabase;
  }

  @override
  Future<void> insertEnvelope(EnvelopeRow row) async {
    final e = row.envelope;
    final web.IDBTransaction tx;
    try {
      tx = _open.transaction(
        <JSString>[_index.toJS, _blobs.toJS].toJS,
        'readwrite',
      );
      tx.objectStore(_index).put(_indexRecord(row));
      tx
          .objectStore(_blobs)
          .put(
            _record(<String, JSAny?>{
              'batchId': e.batchId.toJS,
              'wrappedKey': e.wrappedKey.toJS,
              'iv': e.iv.toJS,
              'tag': e.tag.toJS,
              'ciphertext': e.ciphertext.toJS,
            }),
          );
    } on StateError {
      rethrow;
    } catch (error) {
      // Firefox 159, once a write has hit the quota, refuses the next write
      // synchronously with InvalidStateError ("did not allow mutations")
      // until space is freed. The adapter never upgrades or closes the
      // database under a write, so here that name means "full".
      final name = _thrownName(error);
      if (name == 'QuotaExceededError' || name == 'InvalidStateError') {
        throw StorageFullException(name);
      }
      rethrow;
    }
    await _done(tx);
  }

  /// The DOMException name of a synchronously thrown browser error, or null.
  static String? _thrownName(Object error) {
    final text = error.toString();
    for (final name in const ['QuotaExceededError', 'InvalidStateError']) {
      if (text.startsWith(name) || text.contains(': $name')) return name;
    }
    return null;
  }

  @override
  Future<List<EnvelopeIndexRow>> listIndex() async {
    final tx = _open.transaction(_index.toJS, 'readonly');
    final result = await _await(tx.objectStore(_index).getAll());
    final records = (result! as JSArray<JSAny?>).toDart;
    final rows =
        <EnvelopeIndexRow>[
          for (final record in records) _toIndexRow(record! as JSObject),
        ]..sort((a, b) {
          final byTime = a.createdAt.compareTo(b.createdAt);
          return byTime != 0 ? byTime : a.batchId.compareTo(b.batchId);
        });
    return rows;
  }

  @override
  Future<List<EnvelopeRow>> fetch(Iterable<String> batchIds) async {
    final ids = batchIds.toList();
    if (ids.isEmpty) return <EnvelopeRow>[];
    final tx = _open.transaction(
      <JSString>[_index.toJS, _blobs.toJS].toJS,
      'readonly',
    );
    final indexStore = tx.objectStore(_index);
    final blobStore = tx.objectStore(_blobs);
    final indexRequests = [
      for (final id in ids) _await(indexStore.get(id.toJS)),
    ];
    final blobRequests = [for (final id in ids) _await(blobStore.get(id.toJS))];
    final indexes = await Future.wait(indexRequests);
    final blobs = await Future.wait(blobRequests);

    final rows = <EnvelopeRow>[];
    for (var i = 0; i < ids.length; i++) {
      final index = indexes[i];
      final blob = blobs[i];
      if (index == null || blob == null) continue;
      rows.add(_toRow(index as JSObject, blob as JSObject));
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
    final ids = batchIds.toList();
    if (ids.isEmpty) return;
    final tx = _open.transaction(
      <JSString>[_index.toJS, _blobs.toJS].toJS,
      'readwrite',
    );
    final done = _done(tx);
    for (final id in ids) {
      tx.objectStore(_index).delete(id.toJS);
      tx.objectStore(_blobs).delete(id.toJS);
    }
    await done;
  }

  @override
  Future<void> patch(
    Iterable<String> batchIds, {
    int attemptsDelta = 0,
    int? lastAttemptAt,
    int? uploadState,
    int? uploadedAt,
  }) async {
    final ids = batchIds.toList();
    if (ids.isEmpty) return;
    final tx = _open.transaction(_index.toJS, 'readwrite');
    final done = _done(tx);
    final store = tx.objectStore(_index);
    for (final id in ids) {
      final record = await _await(store.get(id.toJS));
      if (record == null) continue;
      final object = record as JSObject;
      final attempts = _int(object, 'attempts') ?? 0;
      object.setProperty('attempts'.toJS, (attempts + attemptsDelta).toJS);
      if (lastAttemptAt != null) {
        object.setProperty('lastAttemptAt'.toJS, lastAttemptAt.toJS);
      }
      if (uploadState != null) {
        object.setProperty('uploadState'.toJS, uploadState.toJS);
      }
      if (uploadedAt != null) {
        object.setProperty('uploadedAt'.toJS, uploadedAt.toJS);
      }
      store.put(object);
    }
    await done;
  }

  @override
  Future<void> clearAll() async {
    final tx = _open.transaction(
      <JSString>[_index.toJS, _blobs.toJS].toJS,
      'readwrite',
    );
    final done = _done(tx);
    tx.objectStore(_index).clear();
    tx.objectStore(_blobs).clear();
    await done;
  }

  @override
  Future<String?> readMeta(String key) async {
    final tx = _open.transaction(_meta.toJS, 'readonly');
    final record = await _await(tx.objectStore(_meta).get(key.toJS));
    if (record == null) return null;
    return (record as JSObject).getProperty<JSString?>('value'.toJS)?.toDart;
  }

  @override
  Future<void> writeMeta(String key, String value) async {
    final tx = _open.transaction(_meta.toJS, 'readwrite');
    final done = _done(tx);
    tx
        .objectStore(_meta)
        .put(_record(<String, JSAny?>{'key': key.toJS, 'value': value.toJS}));
    await done;
  }

  @override
  Future<void> close() async {
    _db?.close();
    _db = null;
  }

  /// Deletes the whole database. Used by tests.
  Future<void> deleteDatabase() async {
    await close();
    await _await(web.window.indexedDB.deleteDatabase(databaseName));
  }

  static JSObject _record(Map<String, JSAny?> fields) {
    final object = JSObject();
    fields.forEach((key, value) => object.setProperty(key.toJS, value));
    return object;
  }

  static JSObject _indexRecord(EnvelopeRow row) {
    final e = row.envelope;
    return _record(<String, JSAny?>{
      'batchId': e.batchId.toJS,
      'projectId': e.projectId.toJS,
      'createdAt': e.createdAt.millisecondsSinceEpoch.toJS,
      'eventCount': e.eventCount.toJS,
      'payloadSize': e.payloadSize.toJS,
      'sizeBytes': e.storedBytes.toJS,
      'seqMin': e.seqMin.toJS,
      'seqMax': e.seqMax.toJS,
      'minTs': e.minTs.toJS,
      'maxTs': e.maxTs.toJS,
      'topLevels': e.topLevels.toJS,
      'uploadState': row.uploadState.toJS,
      'attempts': row.attempts.toJS,
      'lastAttemptAt': row.lastAttemptAt?.toJS,
      'uploadedAt': row.uploadedAt?.toJS,
    });
  }

  static int? _int(JSObject object, String name) =>
      object.getProperty<JSNumber?>(name.toJS)?.toDartInt;

  static String _string(JSObject object, String name) =>
      object.getProperty<JSString>(name.toJS).toDart;

  static Uint8List _bytes(JSObject object, String name) =>
      Uint8List.fromList(object.getProperty<JSUint8Array>(name.toJS).toDart);

  static EnvelopeIndexRow _toIndexRow(JSObject o) => EnvelopeIndexRow(
    batchId: _string(o, 'batchId'),
    createdAt: _int(o, 'createdAt')!,
    eventCount: _int(o, 'eventCount')!,
    sizeBytes: _int(o, 'sizeBytes')!,
    uploadState: _int(o, 'uploadState')!,
    attempts: _int(o, 'attempts')!,
    lastAttemptAt: _int(o, 'lastAttemptAt'),
    uploadedAt: _int(o, 'uploadedAt'),
  );

  static EnvelopeRow _toRow(JSObject index, JSObject blob) => EnvelopeRow(
    envelope: SealedEnvelope(
      batchId: _string(index, 'batchId'),
      projectId: _string(index, 'projectId'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        _int(index, 'createdAt')!,
        isUtc: true,
      ),
      eventCount: _int(index, 'eventCount')!,
      wrappedKey: _bytes(blob, 'wrappedKey'),
      iv: _bytes(blob, 'iv'),
      tag: _bytes(blob, 'tag'),
      ciphertext: _bytes(blob, 'ciphertext'),
      seqMin: _int(index, 'seqMin')!,
      seqMax: _int(index, 'seqMax')!,
      minTs: _int(index, 'minTs')!,
      maxTs: _int(index, 'maxTs')!,
      topLevels: _string(index, 'topLevels'),
      payloadSize: _int(index, 'payloadSize')!,
    ),
    uploadState: _int(index, 'uploadState')!,
    attempts: _int(index, 'attempts')!,
    lastAttemptAt: _int(index, 'lastAttemptAt'),
    uploadedAt: _int(index, 'uploadedAt'),
  );

  /// Completes with the request's result, or fails with a mapped error.
  static Future<JSAny?> _await(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) {
      if (!completer.isCompleted) completer.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(_mapError(request.error));
      }
    }).toJS;
    return completer.future;
  }

  /// Completes when the transaction has committed.
  ///
  /// Fails only on `abort`, which always follows a request `error` that is not
  /// prevented. At the earlier `error` event `tx.error` can still be null
  /// (Firefox reports a quota failure that way), so the request's own error is
  /// remembered and used when the transaction has none.
  static Future<void> _done(web.IDBTransaction tx) {
    final completer = Completer<void>();
    web.DOMException? requestError;
    tx.oncomplete = ((web.Event _) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    tx.onerror = ((web.Event event) {
      final target = event.target;
      if (target != null && target.isA<web.IDBRequest>()) {
        requestError ??= (target as web.IDBRequest).error;
      }
    }).toJS;
    tx.onabort = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(_mapError(tx.error ?? requestError));
      }
    }).toJS;
    return completer.future;
  }

  static Object _mapError(web.DOMException? error) {
    final name = error?.name;
    if (name == 'QuotaExceededError') return StorageFullException(name);
    return StateError('IndexedDB error: ${name ?? 'unknown'}');
  }
}
