// Selects the browser page-event source at compile time. Only the web build
// touches `package:web`; every other platform gets an empty stream.
export 'page_events_stub.dart'
    if (dart.library.js_interop) 'page_events_web.dart';
