/// What asked for an upload cycle.
enum UploadTrigger {
  /// The periodic timer.
  interval,

  /// Enough data is waiting (event count or bytes).
  threshold,

  /// Connectivity came back.
  connectivity,

  /// The app returned to the foreground.
  resume,

  /// `SealedTrace.flush()`.
  manual,

  /// The first cycle after `init`; also retries dead letters once.
  coldStart,

  /// A scheduled retry after a failure.
  retry,
}
