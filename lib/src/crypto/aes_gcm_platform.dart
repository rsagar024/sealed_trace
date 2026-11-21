// Selects, at compile time, where large AES-GCM jobs run: a background
// isolate on native platforms, the browser's WebCrypto on the web. Neither
// `dart:io` nor `dart:js_interop` enters the other platform's compile graph.
export 'aes_gcm_platform_stub.dart'
    if (dart.library.io) 'aes_gcm_platform_io.dart'
    if (dart.library.js_interop) 'aes_gcm_platform_web.dart';
