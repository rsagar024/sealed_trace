// Chooses the storage implementation at compile time: SQLite through drift on
// `dart:io` platforms, IndexedDB in browsers. Neither `dart:ffi` nor drift is
// reachable from the web build.
export 'open_storage_stub.dart'
    if (dart.library.io) 'open_storage_io.dart'
    if (dart.library.js_interop) 'open_storage_web.dart';
