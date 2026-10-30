import 'dart:typed_data';

import 'package:sealed_trace/src/model/sealed_envelope.dart';

int _counter = 0;

/// A deterministic envelope with recognizable byte patterns. Web-safe.
SealedEnvelope makeEnvelope({
  String? id,
  DateTime? createdAt,
  int eventCount = 1,
  int ciphertextLength = 64,
  int seed = 1,
  int seqMin = 1,
  int seqMax = 1,
  String topLevels = 'info',
  String projectId = 'project-1',
}) {
  _counter++;
  Uint8List fill(int length, int offset) => Uint8List.fromList(
    List<int>.generate(length, (i) => (i * 31 + seed + offset) & 0xff),
  );
  final at =
      createdAt ??
      DateTime.utc(2026, 1, 1, 10).add(Duration(milliseconds: _counter));
  return SealedEnvelope(
    batchId: id ?? 'batch-${_counter.toString().padLeft(6, '0')}',
    projectId: projectId,
    createdAt: at,
    eventCount: eventCount,
    wrappedKey: fill(256, 1),
    iv: fill(12, 2),
    tag: fill(16, 3),
    ciphertext: fill(ciphertextLength, 4),
    seqMin: seqMin,
    seqMax: seqMax,
    minTs: at.millisecondsSinceEpoch,
    maxTs: at.millisecondsSinceEpoch + 5,
    topLevels: topLevels,
    payloadSize: ciphertextLength,
  );
}
