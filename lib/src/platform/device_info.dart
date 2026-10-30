// Selects the platform reader at compile time so that `dart:io` never enters
// the web compile graph.
export 'device_info_stub.dart'
    if (dart.library.io) 'device_info_io.dart'
    if (dart.library.js_interop) 'device_info_web.dart';
