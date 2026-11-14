import 'crypto_backend.dart';

/// Where large AES-GCM jobs run. Without a known platform: inline.
AesGcmOffload platformAesGcmOffload() => runAesGcm;

/// Payload size above which [platformAesGcmOffload] is used.
const int platformOffloadThresholdBytes = 8 * 1024;
