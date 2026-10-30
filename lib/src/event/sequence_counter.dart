import 'dart:async';

/// Persists the sequence high-water mark across app runs.
abstract interface class SequenceStore {
  /// The highest sequence number reserved so far, or 0 on a fresh install.
  Future<int> readHighWater();

  /// Records a new high-water mark.
  Future<void> writeHighWater(int value);
}

/// A [SequenceStore] that forgets everything on restart.
///
/// Used until the persisted store arrives with local storage.
class InMemorySequenceStore implements SequenceStore {
  /// Creates a store starting at [highWater].
  InMemorySequenceStore([this._highWater = 0]);

  int _highWater;

  @override
  Future<int> readHighWater() async => _highWater;

  @override
  Future<void> writeHighWater(int value) async {
    _highWater = value;
  }
}

/// Hands out strictly increasing sequence numbers without awaiting I/O.
///
/// Numbers are reserved from the [SequenceStore] in blocks. A crash can skip
/// the rest of a block, so there may be gaps, but a number is never reused.
class SequenceCounter {
  /// Creates a counter that continues after [highWater].
  SequenceCounter(
    this._store, {
    required int highWater,
    this.blockSize = 100,
    void Function(Object error, StackTrace stack)? onError,
  }) : _next = highWater + 1,
       _reservedTo = highWater,
       _onError = onError;

  final SequenceStore _store;
  final void Function(Object error, StackTrace stack)? _onError;

  /// How many numbers are reserved per store write.
  final int blockSize;

  int _next;
  int _reservedTo;
  Future<void> _pending = Future<void>.value();

  /// Returns the next sequence number.
  int next() {
    if (_next > _reservedTo) {
      _reservedTo += blockSize;
      final target = _reservedTo;
      // Writes are chained so they land in order and can be awaited on close.
      _pending = _pending.then((_) => _store.writeHighWater(target)).catchError(
        (Object e, StackTrace s) {
          _onError?.call(e, s);
        },
      );
    }
    return _next++;
  }

  /// Completes when every reservation written so far has reached the store.
  /// Never completes with an error.
  Future<void> settle() => _pending;
}
