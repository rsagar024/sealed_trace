import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/event/sequence_counter.dart';

class _FailingStore implements SequenceStore {
  @override
  Future<int> readHighWater() async => 0;

  @override
  Future<void> writeHighWater(int value) => Future.error(StateError('disk'));
}

void main() {
  test('starts at highWater + 1', () {
    final c = SequenceCounter(InMemorySequenceStore(), highWater: 41);
    expect(c.next(), 42);
    expect(c.next(), 43);
  });

  test('reserves in blocks and persists the high-water mark', () async {
    final store = InMemorySequenceStore();
    final c = SequenceCounter(store, highWater: 0, blockSize: 100);

    c.next();
    await Future<void>.delayed(Duration.zero);
    expect(await store.readHighWater(), 100);

    for (var i = 0; i < 99; i++) {
      c.next();
    }
    await Future<void>.delayed(Duration.zero);
    expect(await store.readHighWater(), 100);

    c.next(); // 101 crosses into the next block
    await Future<void>.delayed(Duration.zero);
    expect(await store.readHighWater(), 200);
  });

  test('a restart never reuses a number', () async {
    final store = InMemorySequenceStore();
    final first = SequenceCounter(store, highWater: 0);
    var last = 0;
    for (var i = 0; i < 30; i++) {
      last = first.next();
    }
    await Future<void>.delayed(Duration.zero);

    final second = SequenceCounter(
      store,
      highWater: await store.readHighWater(),
    );
    expect(second.next(), greaterThan(last));
  });

  test('a failing store reports and numbering continues', () async {
    final errors = <Object>[];
    final c = SequenceCounter(
      _FailingStore(),
      highWater: 0,
      onError: (e, _) => errors.add(e),
    );
    expect(c.next(), 1);
    expect(c.next(), 2);
    await Future<void>.delayed(Duration.zero);
    expect(errors, hasLength(1));
  });
}
