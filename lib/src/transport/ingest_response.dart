import 'dart:convert';

/// One envelope the server refused, with its stated reason.
class IngestRejection {
  /// Creates a rejection.
  const IngestRejection(this.batchId, this.reason);

  /// The refused batch.
  final String batchId;

  /// The server's reason, or `unknown` when it gave none.
  final String reason;
}

/// What happened to one ingest request.
sealed class IngestOutcome {
  const IngestOutcome();
}

/// HTTP 202 with a readable body: the server saw the request.
///
/// Rows may be deleted only for batch ids in [accepted] or [duplicate].
final class IngestAccepted extends IngestOutcome {
  /// Creates the outcome.
  const IngestAccepted({
    required this.accepted,
    required this.duplicate,
    required this.rejected,
  });

  /// Batches newly accepted.
  final Set<String> accepted;

  /// Batches the server already had.
  final Set<String> duplicate;

  /// Batches refused, with reasons.
  final List<IngestRejection> rejected;
}

/// HTTP 401 or 403: the API key is invalid or revoked.
final class IngestUnauthorized extends IngestOutcome {
  /// Creates the outcome.
  const IngestUnauthorized(this.status);

  /// 401 or 403.
  final int status;
}

/// HTTP 413: the request was too large.
final class IngestTooLarge extends IngestOutcome {
  /// Creates the outcome.
  const IngestTooLarge();
}

/// HTTP 429: the server asked us to slow down.
final class IngestRateLimited extends IngestOutcome {
  /// Creates the outcome.
  const IngestRateLimited(this.retryAfter);

  /// The server's requested wait, if it gave a usable one.
  final Duration? retryAfter;
}

/// Any other status, or a 202 whose body could not be read. Retryable.
final class IngestServerError extends IngestOutcome {
  /// Creates the outcome.
  const IngestServerError(this.status, this.description);

  /// The HTTP status, or 0 when there was no usable response.
  final int status;

  /// A short description that never contains request headers or the API key.
  final String description;
}

/// The request never completed because of a network problem. Retryable.
final class IngestNetworkError extends IngestOutcome {
  /// Creates the outcome.
  const IngestNetworkError(this.description);

  /// The error category (never the exception itself, which could hold headers).
  final String description;
}

/// The request exceeded the time limit. Retryable.
final class IngestTimeout extends IngestOutcome {
  /// Creates the outcome.
  const IngestTimeout();
}

/// The request was cancelled by us, for example on dispose. No attempt counts.
final class IngestCancelled extends IngestOutcome {
  /// Creates the outcome.
  const IngestCancelled();
}

/// Parses the body of a 202 response.
///
/// Unknown fields are ignored and missing lists count as empty. Returns null
/// when the body is not a JSON object or a field has the wrong shape.
IngestAccepted? parseAcceptedBody(String? body) {
  if (body == null || body.trim().isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;

  Set<String>? ids(Object? value) {
    if (value == null) return <String>{};
    if (value is! List) return null;
    final out = <String>{};
    for (final item in value) {
      if (item is! String) return null;
      out.add(item);
    }
    return out;
  }

  final accepted = ids(decoded['accepted']);
  final duplicate = ids(decoded['duplicate']);
  if (accepted == null || duplicate == null) return null;

  final rejected = <IngestRejection>[];
  final rawRejected = decoded['rejected'];
  if (rawRejected != null) {
    if (rawRejected is! List) return null;
    for (final item in rawRejected) {
      if (item is! Map || item['batchId'] is! String) return null;
      final reason = item['reason'];
      rejected.add(
        IngestRejection(
          item['batchId'] as String,
          reason is String && reason.isNotEmpty ? reason : 'unknown',
        ),
      );
    }
  }
  return IngestAccepted(
    accepted: accepted,
    duplicate: duplicate,
    rejected: rejected,
  );
}
