import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/event/metadata_normalizer.dart';

class _Thrower {
  @override
  String toString() => throw StateError('no');
}

void main() {
  test('null and empty give an empty map', () {
    expect(MetadataNormalizer.normalize(null), isEmpty);
    expect(MetadataNormalizer.normalize({}), isEmpty);
  });

  test('JSON types pass through', () {
    final out = MetadataNormalizer.normalize({
      'a': 1,
      'b': 1.5,
      'c': true,
      'd': null,
      'e': 'x',
      'f': [1, 'two'],
      'g': {'h': 1},
    });
    expect(out, {
      'a': 1,
      'b': 1.5,
      'c': true,
      'd': null,
      'e': 'x',
      'f': [1, 'two'],
      'g': {'h': 1},
    });
  });

  test('non-JSON values become strings and the result encodes', () {
    final out = MetadataNormalizer.normalize({
      'when': DateTime.utc(2026, 1, 1),
      'dur': const Duration(seconds: 2),
      'nan': double.nan,
      'inf': double.infinity,
      'uri': Uri.parse('https://x.com'),
      'bad': _Thrower(),
      1: 'int key',
    });
    expect(out['when'], '2026-01-01T00:00:00.000Z');
    expect(out['dur'], '0:00:02.000000');
    expect(out['nan'], 'NaN');
    expect(out['inf'], 'Infinity');
    expect(out['uri'], 'https://x.com');
    expect(out['bad'], '[unprintable]');
    expect(out['1'], 'int key');
    expect(() => jsonEncode(out), returnsNormally);
  });

  test('cycles are replaced with a marker', () {
    final map = <String, dynamic>{'name': 'loop'};
    map['self'] = map;
    final list = <dynamic>[];
    list.add(list);
    final out = MetadataNormalizer.normalize({'m': map, 'l': list});
    expect((out['m'] as Map)['self'], '[circular]');
    expect((out['l'] as List).single, '[circular]');
    expect(() => jsonEncode(out), returnsNormally);
  });

  test('the same object used twice is not a cycle', () {
    final shared = {'k': 1};
    final out = MetadataNormalizer.normalize({'a': shared, 'b': shared});
    expect(out['a'], {'k': 1});
    expect(out['b'], {'k': 1});
  });

  test('depth is capped', () {
    Object nested = 'leaf';
    for (var i = 0; i < 10; i++) {
      nested = {'n': nested};
    }
    final out = MetadataNormalizer.normalize({'root': nested});
    var cursor = out['root'];
    var depth = 0;
    while (cursor is Map) {
      cursor = cursor['n'];
      depth++;
    }
    expect(cursor, '[max depth]');
    expect(depth, lessThan(MetadataNormalizer.maxDepth));
  });

  test('total entries are capped', () {
    final out = MetadataNormalizer.normalize({
      for (var i = 0; i < 500; i++) 'k$i': i,
    });
    expect(out.length, MetadataNormalizer.maxEntries);

    final nested = MetadataNormalizer.normalize({
      'list': List.generate(500, (i) => i),
    });
    expect((nested['list'] as List).length, MetadataNormalizer.maxEntries - 1);
  });

  test('an endless iterable cannot hang the walk', () {
    Iterable<int> forever() sync* {
      var i = 0;
      while (true) {
        yield i++;
      }
    }

    final out = MetadataNormalizer.normalize({'x': forever()});
    expect((out['x'] as List).length, MetadataNormalizer.maxEntries - 1);
  });

  test('the input is not mutated', () {
    final input = {
      'a': [1, 2],
    };
    MetadataNormalizer.normalize(input);
    expect(input, {
      'a': [1, 2],
    });
  });
}
