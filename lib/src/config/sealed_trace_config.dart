import 'dart:typed_data';

import '../model/environment.dart';
import '../model/log_level.dart';
import 'mask_config.dart';
import 'network_log_config.dart';
import 'retention_config.dart';
import 'upload_config.dart';

/// An AES-256-GCM encryption supplied by the app, typically from platform
/// crypto (CommonCrypto, Conscrypt, Android Keystore) through a plugin.
///
/// It must encrypt [plaintext] under the 32-byte [key] and 12-byte [iv],
/// authenticate [aad], and return the ciphertext (as long as the plaintext)
/// and the 16-byte tag separately. See [SealedTraceConfig.aesGcmEncryptor].
typedef AesGcmEncryptor =
    Future<({Uint8List ciphertext, Uint8List tag})> Function(
      Uint8List key,
      Uint8List iv,
      Uint8List plaintext,
      Uint8List aad,
    );

/// Top-level configuration passed to `SealedTrace.init`.
class SealedTraceConfig {
  /// Creates a configuration.
  const SealedTraceConfig({
    required this.baseUrl,
    required this.projectId,
    required this.apiKey,
    required this.publicKeyPem,
    required this.appName,
    this.env = SealedTraceEnv.prod,
    this.minLevel = LogLevel.verbose,
    this.enabled = true,
    this.maskConfig = const MaskConfig(),
    this.uploadConfig = const UploadConfig(),
    this.retentionConfig = const RetentionConfig(),
    this.networkLogConfig = const NetworkLogConfig(),
    this.verboseInternalLogs = false,
    this.databaseDirectory,
    this.sendUserDisplayName = false,
    this.allowInsecureHttp = false,
    this.aesGcmEncryptor,
  });

  /// Server base URL. Uploads go to `{baseUrl}/api/v1/ingest/logs`.
  ///
  /// For the hosted SealedTrace server, use `https://sealedtrace.duckdns.org`.
  final String baseUrl;

  /// Project identifier (uuid) issued by the SealedTrace platform.
  ///
  /// Create an account and a project at https://sealedtrace.duckdns.org to
  /// get one.
  final String projectId;

  /// Project API key sent as `X-Api-Key`.
  ///
  /// Each environment of the project has its own key, shown in the console at
  /// https://sealedtrace.duckdns.org.
  ///
  /// A publishable identifier, not a secret: anything compiled into an app
  /// can be extracted. Rely on server-side rate limits and, optionally,
  /// `UploadConfig.attestationTokenProvider` to tell genuine apps apart.
  final String apiKey;

  /// Project RSA public key (2048, 3072 or 4096 bits) in PEM form, copied
  /// from the project's settings at https://sealedtrace.duckdns.org. Only the
  /// server holds the private key, so the device can never read logs back.
  final String publicKeyPem;

  /// Name of the host application.
  final String appName;

  /// Deployment environment reported with every event.
  final SealedTraceEnv env;

  /// Events below this level are dropped.
  final LogLevel minLevel;

  /// When false, every logging call is a no-op.
  final bool enabled;

  /// Masking (PII redaction) settings.
  final MaskConfig maskConfig;

  /// Upload scheduling and retry settings.
  final UploadConfig uploadConfig;

  /// Local retention limits.
  final RetentionConfig retentionConfig;

  /// Network interceptor settings.
  final NetworkLogConfig networkLogConfig;

  /// Prints the SDK's own diagnostics to the console. Never logs content.
  final bool verboseInternalLogs;

  /// Database directory for pure-Dart apps on io platforms. When null the
  /// `path_provider` application support directory is used.
  final String? databaseDirectory;

  /// When true, also sends the name passed to `SealedTrace.setUser(name:)`,
  /// never masked, as `ctx.userDisplayName`, so the console's Users tab can
  /// show it. Defaults to false: no readable name leaves the device unless
  /// you opt in.
  ///
  /// It travels only inside the sealed envelope, but the server can read it.
  /// `MaskConfig.maskUserName` does not affect it: it only controls
  /// `ctx.userName`, which is sent as given by default.
  final bool sendUserDisplayName;

  /// Allows a cleartext `http://` [baseUrl] when [env] is not `dev` or
  /// `local`. Defaults to false, so such a config leaves the SDK disabled.
  ///
  /// Over plain HTTP anyone on the network path can read the `X-Api-Key`
  /// header, and an active attacker can forge the server's acknowledgement
  /// so the device deletes every pending log. Never enable it in production.
  final bool allowInsecureHttp;

  /// An optional platform AES-256-GCM, used instead of the built-in pure-Dart
  /// cipher, which uses lookup tables and is not constant-time.
  ///
  /// At `init` it must reproduce the built-in cipher's output on known-answer
  /// cases; if it does not (or throws, or takes over 5 s) it is reported
  /// through `SealedTrace.onException` and ignored. Once accepted it encrypts
  /// every asynchronous seal. If a call fails or returns the wrong lengths,
  /// that batch is encrypted by the built-in cipher instead and the failure
  /// is reported, so no envelope is lost. The synchronous web page-exit seal
  /// always uses the built-in cipher. Compared by identity.
  final AesGcmEncryptor? aesGcmEncryptor;

  /// Returns a copy with the given fields replaced.
  SealedTraceConfig copyWith({
    String? baseUrl,
    String? projectId,
    String? apiKey,
    String? publicKeyPem,
    String? appName,
    SealedTraceEnv? env,
    LogLevel? minLevel,
    bool? enabled,
    MaskConfig? maskConfig,
    UploadConfig? uploadConfig,
    RetentionConfig? retentionConfig,
    NetworkLogConfig? networkLogConfig,
    bool? verboseInternalLogs,
    String? databaseDirectory,
    bool? sendUserDisplayName,
    bool? allowInsecureHttp,
    AesGcmEncryptor? aesGcmEncryptor,
  }) {
    return SealedTraceConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      projectId: projectId ?? this.projectId,
      apiKey: apiKey ?? this.apiKey,
      publicKeyPem: publicKeyPem ?? this.publicKeyPem,
      appName: appName ?? this.appName,
      env: env ?? this.env,
      minLevel: minLevel ?? this.minLevel,
      enabled: enabled ?? this.enabled,
      maskConfig: maskConfig ?? this.maskConfig,
      uploadConfig: uploadConfig ?? this.uploadConfig,
      retentionConfig: retentionConfig ?? this.retentionConfig,
      networkLogConfig: networkLogConfig ?? this.networkLogConfig,
      verboseInternalLogs: verboseInternalLogs ?? this.verboseInternalLogs,
      databaseDirectory: databaseDirectory ?? this.databaseDirectory,
      sendUserDisplayName: sendUserDisplayName ?? this.sendUserDisplayName,
      allowInsecureHttp: allowInsecureHttp ?? this.allowInsecureHttp,
      aesGcmEncryptor: aesGcmEncryptor ?? this.aesGcmEncryptor,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SealedTraceConfig &&
      baseUrl == other.baseUrl &&
      projectId == other.projectId &&
      apiKey == other.apiKey &&
      publicKeyPem == other.publicKeyPem &&
      appName == other.appName &&
      env == other.env &&
      minLevel == other.minLevel &&
      enabled == other.enabled &&
      maskConfig == other.maskConfig &&
      uploadConfig == other.uploadConfig &&
      retentionConfig == other.retentionConfig &&
      networkLogConfig == other.networkLogConfig &&
      verboseInternalLogs == other.verboseInternalLogs &&
      databaseDirectory == other.databaseDirectory &&
      sendUserDisplayName == other.sendUserDisplayName &&
      allowInsecureHttp == other.allowInsecureHttp &&
      identical(aesGcmEncryptor, other.aesGcmEncryptor);

  @override
  int get hashCode => Object.hash(
    baseUrl,
    projectId,
    apiKey,
    publicKeyPem,
    appName,
    env,
    minLevel,
    enabled,
    maskConfig,
    uploadConfig,
    retentionConfig,
    networkLogConfig,
    verboseInternalLogs,
    databaseDirectory,
    sendUserDisplayName,
    allowInsecureHttp,
    aesGcmEncryptor == null ? 0 : identityHashCode(aesGcmEncryptor),
  );

  // Deliberately omits apiKey so a config never leaks the key into logs.
  @override
  String toString() =>
      'SealedTraceConfig(baseUrl: $baseUrl, projectId: $projectId, '
      'appName: $appName, env: ${env.name}, enabled: $enabled)';
}
