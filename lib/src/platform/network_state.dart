/// Reports the current network type for the `ctx.network` field.
abstract interface class NetworkStateProvider {
  /// One of `wifi`, `mobile`, `none` or `unknown`.
  String current();
}

/// Used until connectivity monitoring is wired in; always `unknown`.
class UnknownNetworkState implements NetworkStateProvider {
  /// Creates the provider.
  const UnknownNetworkState();

  @override
  String current() => 'unknown';
}
