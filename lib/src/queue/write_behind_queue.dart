import 'dart:async';
import 'dart:collection';

import '../event/log_record.dart';

/// Receives a batch of records leaving the queue.
typedef BatchSink = Future<void> Function(List<LogRecord> batch);

/// In-memory buffer that decouples callers from slow work.
///
/// A batch is handed to the sink when the oldest record has waited
/// [flushInterval], when [maxBatchEvents] records are buffered, or when
/// [maxBatchBytes] is reached, whichever comes first. Batches are delivered
/// one at a time and in order. Nothing here ever throws.
class WriteBehindQueue {
  /// Creates a queue.
  WriteBehindQueue({
    required BatchSink sink,
    required void Function(Object error, StackTrace stack) onError,
    void Function()? onDropped,
    this.flushInterval = const Duration(seconds: 2),
    this.maxBatchEvents = 25,
    this.maxBatchBytes = 64 * 1024,
    this.maxQueued = 5000,
  }) : _sink = sink,
       _onError = onError,
       _onDropped = onDropped;

  final BatchSink _sink;
  final void Function(Object error, StackTrace stack) _onError;
  final void Function()? _onDropped;

  /// Longest a record waits before its batch is flushed.
  final Duration flushInterval;

  /// Records per batch.
  final int maxBatchEvents;

  /// Approximate bytes per batch.
  final int maxBatchBytes;

  /// Hard cap on buffered records; beyond it the oldest are dropped.
  final int maxQueued;

  final Queue<LogRecord> _buffer = Queue<LogRecord>();
  int _bytes = 0;
  Timer? _timer;
  Future<void> _inFlight = Future<void>.value();
  bool _disposed = false;

  /// Number of buffered records.
  int get length => _buffer.length;

  /// Whether a flush timer is currently armed. For tests.
  bool get hasPendingTimer => _timer != null;

  /// Buffers [record]. With [immediate] the batch is flushed right away.
  void add(LogRecord record, {bool immediate = false}) {
    if (_disposed) return;
    if (_buffer.length >= maxQueued) {
      _bytes -= _buffer.removeFirst().approxBytes;
      _onDropped?.call();
    }
    _buffer.add(record);
    _bytes += record.approxBytes;

    if (immediate ||
        _buffer.length >= maxBatchEvents ||
        _bytes >= maxBatchBytes) {
      unawaited(flush());
    } else {
      _timer ??= Timer(flushInterval, () {
        _timer = null;
        unawaited(flush());
      });
    }
  }

  /// Hands everything buffered to the sink.
  ///
  /// Completes after the sink has seen the records. Never completes with an
  /// error.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    return _inFlight = _inFlight.then((_) => _drain());
  }

  /// Removes everything buffered, synchronously, as sink-sized batches.
  ///
  /// For the page-exit path, which must not wait for the sink. A batch the
  /// sink is already working on is not included.
  List<List<LogRecord>> takeBatches() {
    _timer?.cancel();
    _timer = null;
    final batches = <List<LogRecord>>[];
    while (_buffer.isNotEmpty) {
      batches.add(_takeBatch());
    }
    return batches;
  }

  /// Throws away everything buffered and not yet handed to the sink.
  /// Returns how many records were dropped.
  int discardPending() {
    final count = _buffer.length;
    _buffer.clear();
    _bytes = 0;
    _timer?.cancel();
    _timer = null;
    return count;
  }

  /// Completes when the batch currently being delivered, if any, is done.
  /// Never completes with an error.
  Future<void> settle() => _inFlight;

  /// Flushes what remains and stops accepting records.
  Future<void> dispose() async {
    _disposed = true;
    await flush();
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _drain() async {
    while (_buffer.isNotEmpty) {
      final batch = _takeBatch();
      try {
        await _sink(batch);
      } catch (error, stack) {
        _onError(error, stack);
      }
    }
    _timer?.cancel();
    _timer = null;
  }

  List<LogRecord> _takeBatch() {
    final batch = <LogRecord>[];
    var bytes = 0;
    while (_buffer.isNotEmpty && batch.length < maxBatchEvents) {
      final next = _buffer.first;
      if (batch.isNotEmpty && bytes + next.approxBytes > maxBatchBytes) break;
      _buffer.removeFirst();
      _bytes -= next.approxBytes;
      bytes += next.approxBytes;
      batch.add(next);
    }
    return batch;
  }
}
