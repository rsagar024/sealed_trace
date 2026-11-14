import 'package:flutter/foundation.dart' show compute;

import 'crypto_backend.dart';

/// Where large AES-GCM jobs run. On native platforms: a background isolate,
/// so sealing never blocks the UI thread. The isolate wipes its copy of the
/// key and plaintext when it is done.
AesGcmOffload platformAesGcmOffload() =>
    (job) => compute(runAesGcmAndWipe, job);
