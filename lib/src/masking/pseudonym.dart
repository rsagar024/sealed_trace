import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Stable, project-scoped pseudonyms for identifiers (L12).
///
/// A pseudonym is `p_` plus 22 base64url characters: the first 128 bits of
/// HMAC-SHA256 over the value, keyed by the project id. The same value gives
/// the same pseudonym within a project, so the console can still group
/// events by user or device, but the raw identifier never leaves the device
/// and pseudonyms from different projects cannot be joined.
///
/// It is pseudonymous, not anonymous: the project id ships in the app, so
/// someone who has it can test guesses. Use it for high-entropy identifiers
/// (device ids, opaque user ids), not to hide an email or phone number.
abstract final class Pseudonym {
  /// Prefix of every pseudonym.
  static const String prefix = 'p_';

  static const String _domain = 'sealed_trace.pseudonym.v1';

  /// The pseudonym of [value] for [projectId].
  static String of(String value, {required String projectId}) {
    final key = utf8.encode('$_domain\n$projectId');
    final mac = Hmac(sha256, key).convert(utf8.encode(value)).bytes;
    return prefix + base64Url.encode(mac.sublist(0, 16)).replaceAll('=', '');
  }
}
