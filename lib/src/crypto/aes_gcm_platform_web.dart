import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'crypto_backend.dart';
import 'gcm.dart';

/// Where large AES-GCM jobs run. On the web: the browser's WebCrypto
/// (`crypto.subtle`), which encrypts natively and asynchronously instead of
/// running the pure-Dart cipher on the main thread. If WebCrypto is missing
/// (an insecure context) or fails, the job runs in pure Dart instead, so
/// sealing never fails because of it.
AesGcmOffload platformAesGcmOffload() => (job) async {
  try {
    final result = await webCryptoAesGcm(job);
    webCryptoUses++;
    return result;
  } catch (_) {
    webCryptoFallbacks++;
    return runAesGcm(job);
  }
};

/// Payload size above which [platformAesGcmOffload] is used. On the web,
/// every asynchronous seal uses WebCrypto: the browser's AES is native and
/// constant-time, unlike the table-based pure-Dart cipher (L5).
const int platformOffloadThresholdBytes = 0;

/// How many jobs fell back to pure Dart. For diagnostics and the web check.
int webCryptoFallbacks = 0;

/// How many jobs WebCrypto encrypted. For diagnostics and the web check.
int webCryptoUses = 0;

/// AES-256-GCM of [job] with WebCrypto, with a 128-bit tag and the job's
/// additional data. Throws if WebCrypto is unavailable.
///
/// The output is byte-identical to [AesGcm256.encrypt]: WebCrypto returns
/// the ciphertext with the tag appended, which is split here.
Future<AesGcmResult> webCryptoAesGcm(AesGcmJob job) async {
  final subtle = web.window.crypto.subtle;
  final key = await subtle
      .importKey(
        'raw',
        job.key.toJS,
        'AES-GCM'.toJS,
        false,
        <JSString>['encrypt'.toJS].toJS,
      )
      .toDart;
  final params = _AesGcmParams(
    name: 'AES-GCM',
    iv: job.iv.toJS,
    additionalData: (job.aad ?? Uint8List(0)).toJS,
    tagLength: AesGcm256.tagSize * 8,
  );
  final result = await subtle.encrypt(params, key, job.plaintext.toJS).toDart;
  final sealed = (result! as JSArrayBuffer).toDart.asUint8List();
  final split = sealed.length - AesGcm256.tagSize;
  if (split != job.plaintext.length) {
    throw StateError('WebCrypto returned an unexpected length');
  }
  return AesGcmResult(
    Uint8List.fromList(sealed.sublist(0, split)),
    Uint8List.fromList(sealed.sublist(split)),
  );
}

/// The `AesGcmParams` dictionary, which `package:web` does not declare.
extension type _AesGcmParams._(JSObject _) implements JSObject {
  external factory _AesGcmParams({
    String name,
    JSUint8Array iv,
    JSUint8Array additionalData,
    int tagLength,
  });
}
