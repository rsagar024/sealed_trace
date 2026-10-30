import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Keeps platform-only libraries out of the shared code, so every target
/// compiles: `dart:io` must not reach the web build, and `dart:js_interop` or
/// `package:web` must not reach the VM builds.
void main() {
  final lib = Directory('lib');
  final files = lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  String rel(File f) =>
      p.posix.joinAll(p.split(p.relative(f.path, from: 'lib')));

  Set<String> importing(RegExp pattern) => {
    for (final f in files)
      if (pattern.hasMatch(
        // Only real import/export lines, not comments or docs.
        f
            .readAsLinesSync()
            .where((l) => RegExp(r'^\s*(import|export)\s').hasMatch(l))
            .join('\n'),
      ))
        rel(f),
  };

  test('dart:io appears only in the io-only files', () {
    expect(importing(RegExp(r"dart:io'")), {
      'src/platform/device_info_io.dart',
      'src/storage/open_storage_io.dart',
    });
  });

  test('browser libraries appear only in the web-only files', () {
    expect(importing(RegExp(r"dart:js_interop'|package:web/")), {
      'src/platform/device_info_web.dart',
      'src/platform/page_events_web.dart',
      'src/storage/envelope_spill_web.dart',
      'src/storage/indexeddb_storage_adapter.dart',
    });
  });

  test('the files named above exist', () {
    expect(files.map(rel), contains('src/platform/page_events_web.dart'));
  });
}
