/// Decides which server rejections are final.
///
/// The spec does not list the server's `reason` values. These are assumed
/// names for failures that retrying cannot fix; any other reason counts as an
/// ordinary failed attempt. Confirm the list with the backend team.
abstract final class DeadLetterPolicy {
  /// Reasons that send an envelope straight to the dead-letter state.
  static const Set<String> permanentReasons = <String>{
    'schema_invalid',
    'invalid_envelope',
    'unsupported_version',
    'too_large',
    'invalid_project',
  };

  /// Whether [reason] means the envelope can never be accepted.
  static bool isPermanent(String reason) =>
      permanentReasons.contains(reason.trim().toLowerCase());
}
