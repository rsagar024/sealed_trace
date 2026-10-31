/// Deployment environment reported with every event as `ctx.env`.
///
/// Use one of the built-in names, or any environment created for the project
/// on the SealedTrace dashboard, such as `SealedTraceEnv('qa')`. Names are
/// 1 to 32 characters of `a-z`, `0-9`, `_` or `-`, starting with a letter or
/// digit; any other name leaves the SDK disabled.
final class SealedTraceEnv {
  /// Creates an environment with the given [name].
  const SealedTraceEnv(this.name);

  /// Local development.
  static const SealedTraceEnv dev = SealedTraceEnv('dev');

  /// Pre-production testing.
  static const SealedTraceEnv staging = SealedTraceEnv('staging');

  /// Production.
  static const SealedTraceEnv prod = SealedTraceEnv('prod');

  /// The name sent with every event, such as `prod` or `qa`.
  final String name;

  /// Whether this is the production environment.
  bool get isProd => name == prod.name;

  @override
  bool operator ==(Object other) =>
      other is SealedTraceEnv && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}
