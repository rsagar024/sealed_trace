import 'crypto_backend.dart';

/// Where large AES-GCM jobs run. Without a known platform: inline.
AesGcmOffload platformAesGcmOffload() => runAesGcm;
