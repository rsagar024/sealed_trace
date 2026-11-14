import 'package:flutter/foundation.dart' show compute;

import 'crypto_backend.dart';

/// Where large AES-GCM jobs run. On native platforms: a background isolate,
/// so sealing never blocks the UI thread.
AesGcmOffload platformAesGcmOffload() =>
    (job) => compute(runAesGcm, job);
