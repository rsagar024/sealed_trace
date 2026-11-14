import '../model/environment.dart';
import '../model/log_level.dart';
import 'mask_config.dart';
import 'network_log_config.dart';
import 'retention_config.dart';
import 'upload_config.dart';

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
  });

  /// Server base URL. Uploads go to `{baseUrl}/api/v1/ingest/logs`.
  final String baseUrl;

  /// Project identifier (uuid) issued by the SealedTrace platform.
  final String projectId;

  /// Project API key sent as `X-Api-Key`.
  ///
  /// A publishable identifier, not a secret: anything compiled into an app
  /// can be extracted. Rely on server-side rate limits and, optionally,
  /// `UploadConfig.attestationTokenProvider` to tell genuine apps apart.
  final String apiKey;

  /// Project RSA-2048 public key in PEM form. Only the server holds the
  /// private key, so the device can never read logs back.
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
  /// `ctx.userName`, which is `***` by default.
  final bool sendUserDisplayName;

  /// Allows a cleartext `http://` [baseUrl] when [env] is not `dev` or
  /// `local`. Defaults to false, so such a config leaves the SDK disabled.
  ///
  /// Over plain HTTP anyone on the network path can read the `X-Api-Key`
  /// header, and an active attacker can forge the server's acknowledgement
  /// so the device deletes every pending log. Never enable it in production.
  final bool allowInsecureHttp;

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
      allowInsecureHttp == other.allowInsecureHttp;

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
  );

  // Deliberately omits apiKey so a config never leaks the key into logs.
  @override
  String toString() =>
      'SealedTraceConfig(baseUrl: $baseUrl, projectId: $projectId, '
      'appName: $appName, env: ${env.name}, enabled: $enabled)';
}
