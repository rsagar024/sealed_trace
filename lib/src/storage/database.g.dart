// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $SealedEnvelopesTable extends SealedEnvelopes
    with TableInfo<$SealedEnvelopesTable, EnvelopeRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SealedEnvelopesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventCountMeta = const VerificationMeta(
    'eventCount',
  );
  @override
  late final GeneratedColumn<int> eventCount = GeneratedColumn<int>(
    'event_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadSizeMeta = const VerificationMeta(
    'payloadSize',
  );
  @override
  late final GeneratedColumn<int> payloadSize = GeneratedColumn<int>(
    'payload_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wrappedKeyMeta = const VerificationMeta(
    'wrappedKey',
  );
  @override
  late final GeneratedColumn<Uint8List> wrappedKey = GeneratedColumn<Uint8List>(
    'wrapped_key',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ivMeta = const VerificationMeta('iv');
  @override
  late final GeneratedColumn<Uint8List> iv = GeneratedColumn<Uint8List>(
    'iv',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagMeta = const VerificationMeta('tag');
  @override
  late final GeneratedColumn<Uint8List> tag = GeneratedColumn<Uint8List>(
    'tag',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ciphertextMeta = const VerificationMeta(
    'ciphertext',
  );
  @override
  late final GeneratedColumn<Uint8List> ciphertext = GeneratedColumn<Uint8List>(
    'ciphertext',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uploadStateMeta = const VerificationMeta(
    'uploadState',
  );
  @override
  late final GeneratedColumn<int> uploadState = GeneratedColumn<int>(
    'upload_state',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastAttemptAtMeta = const VerificationMeta(
    'lastAttemptAt',
  );
  @override
  late final GeneratedColumn<int> lastAttemptAt = GeneratedColumn<int>(
    'last_attempt_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seqMinMeta = const VerificationMeta('seqMin');
  @override
  late final GeneratedColumn<int> seqMin = GeneratedColumn<int>(
    'seq_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seqMaxMeta = const VerificationMeta('seqMax');
  @override
  late final GeneratedColumn<int> seqMax = GeneratedColumn<int>(
    'seq_max',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minTsMeta = const VerificationMeta('minTs');
  @override
  late final GeneratedColumn<int> minTs = GeneratedColumn<int>(
    'min_ts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _maxTsMeta = const VerificationMeta('maxTs');
  @override
  late final GeneratedColumn<int> maxTs = GeneratedColumn<int>(
    'max_ts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topLevelsMeta = const VerificationMeta(
    'topLevels',
  );
  @override
  late final GeneratedColumn<String> topLevels = GeneratedColumn<String>(
    'top_levels',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uploadedAtMeta = const VerificationMeta(
    'uploadedAt',
  );
  @override
  late final GeneratedColumn<int> uploadedAt = GeneratedColumn<int>(
    'uploaded_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    batchId,
    projectId,
    createdAt,
    eventCount,
    payloadSize,
    wrappedKey,
    iv,
    tag,
    ciphertext,
    uploadState,
    attempts,
    lastAttemptAt,
    seqMin,
    seqMax,
    minTs,
    maxTs,
    topLevels,
    uploadedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sealed_envelopes';
  @override
  VerificationContext validateIntegrity(
    Insertable<EnvelopeRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_batchIdMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('event_count')) {
      context.handle(
        _eventCountMeta,
        eventCount.isAcceptableOrUnknown(data['event_count']!, _eventCountMeta),
      );
    } else if (isInserting) {
      context.missing(_eventCountMeta);
    }
    if (data.containsKey('payload_size')) {
      context.handle(
        _payloadSizeMeta,
        payloadSize.isAcceptableOrUnknown(
          data['payload_size']!,
          _payloadSizeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadSizeMeta);
    }
    if (data.containsKey('wrapped_key')) {
      context.handle(
        _wrappedKeyMeta,
        wrappedKey.isAcceptableOrUnknown(data['wrapped_key']!, _wrappedKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_wrappedKeyMeta);
    }
    if (data.containsKey('iv')) {
      context.handle(_ivMeta, iv.isAcceptableOrUnknown(data['iv']!, _ivMeta));
    } else if (isInserting) {
      context.missing(_ivMeta);
    }
    if (data.containsKey('tag')) {
      context.handle(
        _tagMeta,
        tag.isAcceptableOrUnknown(data['tag']!, _tagMeta),
      );
    } else if (isInserting) {
      context.missing(_tagMeta);
    }
    if (data.containsKey('ciphertext')) {
      context.handle(
        _ciphertextMeta,
        ciphertext.isAcceptableOrUnknown(data['ciphertext']!, _ciphertextMeta),
      );
    } else if (isInserting) {
      context.missing(_ciphertextMeta);
    }
    if (data.containsKey('upload_state')) {
      context.handle(
        _uploadStateMeta,
        uploadState.isAcceptableOrUnknown(
          data['upload_state']!,
          _uploadStateMeta,
        ),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
        _lastAttemptAtMeta,
        lastAttemptAt.isAcceptableOrUnknown(
          data['last_attempt_at']!,
          _lastAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('seq_min')) {
      context.handle(
        _seqMinMeta,
        seqMin.isAcceptableOrUnknown(data['seq_min']!, _seqMinMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMinMeta);
    }
    if (data.containsKey('seq_max')) {
      context.handle(
        _seqMaxMeta,
        seqMax.isAcceptableOrUnknown(data['seq_max']!, _seqMaxMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMaxMeta);
    }
    if (data.containsKey('min_ts')) {
      context.handle(
        _minTsMeta,
        minTs.isAcceptableOrUnknown(data['min_ts']!, _minTsMeta),
      );
    } else if (isInserting) {
      context.missing(_minTsMeta);
    }
    if (data.containsKey('max_ts')) {
      context.handle(
        _maxTsMeta,
        maxTs.isAcceptableOrUnknown(data['max_ts']!, _maxTsMeta),
      );
    } else if (isInserting) {
      context.missing(_maxTsMeta);
    }
    if (data.containsKey('top_levels')) {
      context.handle(
        _topLevelsMeta,
        topLevels.isAcceptableOrUnknown(data['top_levels']!, _topLevelsMeta),
      );
    } else if (isInserting) {
      context.missing(_topLevelsMeta);
    }
    if (data.containsKey('uploaded_at')) {
      context.handle(
        _uploadedAtMeta,
        uploadedAt.isAcceptableOrUnknown(data['uploaded_at']!, _uploadedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {batchId};
  @override
  EnvelopeRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EnvelopeRecord(
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      eventCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}event_count'],
      )!,
      payloadSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}payload_size'],
      )!,
      wrappedKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}wrapped_key'],
      )!,
      iv: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}iv'],
      )!,
      tag: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}tag'],
      )!,
      ciphertext: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}ciphertext'],
      )!,
      uploadState: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}upload_state'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_attempt_at'],
      ),
      seqMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq_min'],
      )!,
      seqMax: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq_max'],
      )!,
      minTs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}min_ts'],
      )!,
      maxTs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_ts'],
      )!,
      topLevels: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}top_levels'],
      )!,
      uploadedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}uploaded_at'],
      ),
    );
  }

  @override
  $SealedEnvelopesTable createAlias(String alias) {
    return $SealedEnvelopesTable(attachedDatabase, alias);
  }
}

class EnvelopeRecord extends DataClass implements Insertable<EnvelopeRecord> {
  /// uuid-v4 of the batch.
  final String batchId;

  /// Project the batch belongs to.
  final String projectId;

  /// Creation time, epoch milliseconds.
  final int createdAt;

  /// Events inside.
  final int eventCount;

  /// Plaintext JSON size in bytes, before encryption.
  final int payloadSize;

  /// AES key wrapped with the project's RSA public key.
  final Uint8List wrappedKey;

  /// AES-GCM nonce.
  final Uint8List iv;

  /// AES-GCM tag.
  final Uint8List tag;

  /// Encrypted JSON array of events.
  final Uint8List ciphertext;

  /// 0 pending, 1 dead letter.
  final int uploadState;

  /// Failed upload attempts.
  final int attempts;

  /// Time of the last attempt, epoch milliseconds.
  final int? lastAttemptAt;

  /// Smallest event sequence number inside.
  final int seqMin;

  /// Largest event sequence number inside.
  final int seqMax;

  /// Earliest event time inside, epoch milliseconds.
  final int minTs;

  /// Latest event time inside, epoch milliseconds.
  final int maxTs;

  /// Distinct levels inside, comma separated, in severity order.
  final String topLevels;

  /// Set once the server acknowledged the batch, until the row is deleted.
  final int? uploadedAt;
  const EnvelopeRecord({
    required this.batchId,
    required this.projectId,
    required this.createdAt,
    required this.eventCount,
    required this.payloadSize,
    required this.wrappedKey,
    required this.iv,
    required this.tag,
    required this.ciphertext,
    required this.uploadState,
    required this.attempts,
    this.lastAttemptAt,
    required this.seqMin,
    required this.seqMax,
    required this.minTs,
    required this.maxTs,
    required this.topLevels,
    this.uploadedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['batch_id'] = Variable<String>(batchId);
    map['project_id'] = Variable<String>(projectId);
    map['created_at'] = Variable<int>(createdAt);
    map['event_count'] = Variable<int>(eventCount);
    map['payload_size'] = Variable<int>(payloadSize);
    map['wrapped_key'] = Variable<Uint8List>(wrappedKey);
    map['iv'] = Variable<Uint8List>(iv);
    map['tag'] = Variable<Uint8List>(tag);
    map['ciphertext'] = Variable<Uint8List>(ciphertext);
    map['upload_state'] = Variable<int>(uploadState);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<int>(lastAttemptAt);
    }
    map['seq_min'] = Variable<int>(seqMin);
    map['seq_max'] = Variable<int>(seqMax);
    map['min_ts'] = Variable<int>(minTs);
    map['max_ts'] = Variable<int>(maxTs);
    map['top_levels'] = Variable<String>(topLevels);
    if (!nullToAbsent || uploadedAt != null) {
      map['uploaded_at'] = Variable<int>(uploadedAt);
    }
    return map;
  }

  SealedEnvelopesCompanion toCompanion(bool nullToAbsent) {
    return SealedEnvelopesCompanion(
      batchId: Value(batchId),
      projectId: Value(projectId),
      createdAt: Value(createdAt),
      eventCount: Value(eventCount),
      payloadSize: Value(payloadSize),
      wrappedKey: Value(wrappedKey),
      iv: Value(iv),
      tag: Value(tag),
      ciphertext: Value(ciphertext),
      uploadState: Value(uploadState),
      attempts: Value(attempts),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      seqMin: Value(seqMin),
      seqMax: Value(seqMax),
      minTs: Value(minTs),
      maxTs: Value(maxTs),
      topLevels: Value(topLevels),
      uploadedAt: uploadedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(uploadedAt),
    );
  }

  factory EnvelopeRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EnvelopeRecord(
      batchId: serializer.fromJson<String>(json['batchId']),
      projectId: serializer.fromJson<String>(json['projectId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      eventCount: serializer.fromJson<int>(json['eventCount']),
      payloadSize: serializer.fromJson<int>(json['payloadSize']),
      wrappedKey: serializer.fromJson<Uint8List>(json['wrappedKey']),
      iv: serializer.fromJson<Uint8List>(json['iv']),
      tag: serializer.fromJson<Uint8List>(json['tag']),
      ciphertext: serializer.fromJson<Uint8List>(json['ciphertext']),
      uploadState: serializer.fromJson<int>(json['uploadState']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastAttemptAt: serializer.fromJson<int?>(json['lastAttemptAt']),
      seqMin: serializer.fromJson<int>(json['seqMin']),
      seqMax: serializer.fromJson<int>(json['seqMax']),
      minTs: serializer.fromJson<int>(json['minTs']),
      maxTs: serializer.fromJson<int>(json['maxTs']),
      topLevels: serializer.fromJson<String>(json['topLevels']),
      uploadedAt: serializer.fromJson<int?>(json['uploadedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'batchId': serializer.toJson<String>(batchId),
      'projectId': serializer.toJson<String>(projectId),
      'createdAt': serializer.toJson<int>(createdAt),
      'eventCount': serializer.toJson<int>(eventCount),
      'payloadSize': serializer.toJson<int>(payloadSize),
      'wrappedKey': serializer.toJson<Uint8List>(wrappedKey),
      'iv': serializer.toJson<Uint8List>(iv),
      'tag': serializer.toJson<Uint8List>(tag),
      'ciphertext': serializer.toJson<Uint8List>(ciphertext),
      'uploadState': serializer.toJson<int>(uploadState),
      'attempts': serializer.toJson<int>(attempts),
      'lastAttemptAt': serializer.toJson<int?>(lastAttemptAt),
      'seqMin': serializer.toJson<int>(seqMin),
      'seqMax': serializer.toJson<int>(seqMax),
      'minTs': serializer.toJson<int>(minTs),
      'maxTs': serializer.toJson<int>(maxTs),
      'topLevels': serializer.toJson<String>(topLevels),
      'uploadedAt': serializer.toJson<int?>(uploadedAt),
    };
  }

  EnvelopeRecord copyWith({
    String? batchId,
    String? projectId,
    int? createdAt,
    int? eventCount,
    int? payloadSize,
    Uint8List? wrappedKey,
    Uint8List? iv,
    Uint8List? tag,
    Uint8List? ciphertext,
    int? uploadState,
    int? attempts,
    Value<int?> lastAttemptAt = const Value.absent(),
    int? seqMin,
    int? seqMax,
    int? minTs,
    int? maxTs,
    String? topLevels,
    Value<int?> uploadedAt = const Value.absent(),
  }) => EnvelopeRecord(
    batchId: batchId ?? this.batchId,
    projectId: projectId ?? this.projectId,
    createdAt: createdAt ?? this.createdAt,
    eventCount: eventCount ?? this.eventCount,
    payloadSize: payloadSize ?? this.payloadSize,
    wrappedKey: wrappedKey ?? this.wrappedKey,
    iv: iv ?? this.iv,
    tag: tag ?? this.tag,
    ciphertext: ciphertext ?? this.ciphertext,
    uploadState: uploadState ?? this.uploadState,
    attempts: attempts ?? this.attempts,
    lastAttemptAt: lastAttemptAt.present
        ? lastAttemptAt.value
        : this.lastAttemptAt,
    seqMin: seqMin ?? this.seqMin,
    seqMax: seqMax ?? this.seqMax,
    minTs: minTs ?? this.minTs,
    maxTs: maxTs ?? this.maxTs,
    topLevels: topLevels ?? this.topLevels,
    uploadedAt: uploadedAt.present ? uploadedAt.value : this.uploadedAt,
  );
  EnvelopeRecord copyWithCompanion(SealedEnvelopesCompanion data) {
    return EnvelopeRecord(
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      eventCount: data.eventCount.present
          ? data.eventCount.value
          : this.eventCount,
      payloadSize: data.payloadSize.present
          ? data.payloadSize.value
          : this.payloadSize,
      wrappedKey: data.wrappedKey.present
          ? data.wrappedKey.value
          : this.wrappedKey,
      iv: data.iv.present ? data.iv.value : this.iv,
      tag: data.tag.present ? data.tag.value : this.tag,
      ciphertext: data.ciphertext.present
          ? data.ciphertext.value
          : this.ciphertext,
      uploadState: data.uploadState.present
          ? data.uploadState.value
          : this.uploadState,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      seqMin: data.seqMin.present ? data.seqMin.value : this.seqMin,
      seqMax: data.seqMax.present ? data.seqMax.value : this.seqMax,
      minTs: data.minTs.present ? data.minTs.value : this.minTs,
      maxTs: data.maxTs.present ? data.maxTs.value : this.maxTs,
      topLevels: data.topLevels.present ? data.topLevels.value : this.topLevels,
      uploadedAt: data.uploadedAt.present
          ? data.uploadedAt.value
          : this.uploadedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EnvelopeRecord(')
          ..write('batchId: $batchId, ')
          ..write('projectId: $projectId, ')
          ..write('createdAt: $createdAt, ')
          ..write('eventCount: $eventCount, ')
          ..write('payloadSize: $payloadSize, ')
          ..write('wrappedKey: $wrappedKey, ')
          ..write('iv: $iv, ')
          ..write('tag: $tag, ')
          ..write('ciphertext: $ciphertext, ')
          ..write('uploadState: $uploadState, ')
          ..write('attempts: $attempts, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('seqMin: $seqMin, ')
          ..write('seqMax: $seqMax, ')
          ..write('minTs: $minTs, ')
          ..write('maxTs: $maxTs, ')
          ..write('topLevels: $topLevels, ')
          ..write('uploadedAt: $uploadedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    batchId,
    projectId,
    createdAt,
    eventCount,
    payloadSize,
    $driftBlobEquality.hash(wrappedKey),
    $driftBlobEquality.hash(iv),
    $driftBlobEquality.hash(tag),
    $driftBlobEquality.hash(ciphertext),
    uploadState,
    attempts,
    lastAttemptAt,
    seqMin,
    seqMax,
    minTs,
    maxTs,
    topLevels,
    uploadedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EnvelopeRecord &&
          other.batchId == this.batchId &&
          other.projectId == this.projectId &&
          other.createdAt == this.createdAt &&
          other.eventCount == this.eventCount &&
          other.payloadSize == this.payloadSize &&
          $driftBlobEquality.equals(other.wrappedKey, this.wrappedKey) &&
          $driftBlobEquality.equals(other.iv, this.iv) &&
          $driftBlobEquality.equals(other.tag, this.tag) &&
          $driftBlobEquality.equals(other.ciphertext, this.ciphertext) &&
          other.uploadState == this.uploadState &&
          other.attempts == this.attempts &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.seqMin == this.seqMin &&
          other.seqMax == this.seqMax &&
          other.minTs == this.minTs &&
          other.maxTs == this.maxTs &&
          other.topLevels == this.topLevels &&
          other.uploadedAt == this.uploadedAt);
}

class SealedEnvelopesCompanion extends UpdateCompanion<EnvelopeRecord> {
  final Value<String> batchId;
  final Value<String> projectId;
  final Value<int> createdAt;
  final Value<int> eventCount;
  final Value<int> payloadSize;
  final Value<Uint8List> wrappedKey;
  final Value<Uint8List> iv;
  final Value<Uint8List> tag;
  final Value<Uint8List> ciphertext;
  final Value<int> uploadState;
  final Value<int> attempts;
  final Value<int?> lastAttemptAt;
  final Value<int> seqMin;
  final Value<int> seqMax;
  final Value<int> minTs;
  final Value<int> maxTs;
  final Value<String> topLevels;
  final Value<int?> uploadedAt;
  final Value<int> rowid;
  const SealedEnvelopesCompanion({
    this.batchId = const Value.absent(),
    this.projectId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.eventCount = const Value.absent(),
    this.payloadSize = const Value.absent(),
    this.wrappedKey = const Value.absent(),
    this.iv = const Value.absent(),
    this.tag = const Value.absent(),
    this.ciphertext = const Value.absent(),
    this.uploadState = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.seqMin = const Value.absent(),
    this.seqMax = const Value.absent(),
    this.minTs = const Value.absent(),
    this.maxTs = const Value.absent(),
    this.topLevels = const Value.absent(),
    this.uploadedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SealedEnvelopesCompanion.insert({
    required String batchId,
    required String projectId,
    required int createdAt,
    required int eventCount,
    required int payloadSize,
    required Uint8List wrappedKey,
    required Uint8List iv,
    required Uint8List tag,
    required Uint8List ciphertext,
    this.uploadState = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    required int seqMin,
    required int seqMax,
    required int minTs,
    required int maxTs,
    required String topLevels,
    this.uploadedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : batchId = Value(batchId),
       projectId = Value(projectId),
       createdAt = Value(createdAt),
       eventCount = Value(eventCount),
       payloadSize = Value(payloadSize),
       wrappedKey = Value(wrappedKey),
       iv = Value(iv),
       tag = Value(tag),
       ciphertext = Value(ciphertext),
       seqMin = Value(seqMin),
       seqMax = Value(seqMax),
       minTs = Value(minTs),
       maxTs = Value(maxTs),
       topLevels = Value(topLevels);
  static Insertable<EnvelopeRecord> custom({
    Expression<String>? batchId,
    Expression<String>? projectId,
    Expression<int>? createdAt,
    Expression<int>? eventCount,
    Expression<int>? payloadSize,
    Expression<Uint8List>? wrappedKey,
    Expression<Uint8List>? iv,
    Expression<Uint8List>? tag,
    Expression<Uint8List>? ciphertext,
    Expression<int>? uploadState,
    Expression<int>? attempts,
    Expression<int>? lastAttemptAt,
    Expression<int>? seqMin,
    Expression<int>? seqMax,
    Expression<int>? minTs,
    Expression<int>? maxTs,
    Expression<String>? topLevels,
    Expression<int>? uploadedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (batchId != null) 'batch_id': batchId,
      if (projectId != null) 'project_id': projectId,
      if (createdAt != null) 'created_at': createdAt,
      if (eventCount != null) 'event_count': eventCount,
      if (payloadSize != null) 'payload_size': payloadSize,
      if (wrappedKey != null) 'wrapped_key': wrappedKey,
      if (iv != null) 'iv': iv,
      if (tag != null) 'tag': tag,
      if (ciphertext != null) 'ciphertext': ciphertext,
      if (uploadState != null) 'upload_state': uploadState,
      if (attempts != null) 'attempts': attempts,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (seqMin != null) 'seq_min': seqMin,
      if (seqMax != null) 'seq_max': seqMax,
      if (minTs != null) 'min_ts': minTs,
      if (maxTs != null) 'max_ts': maxTs,
      if (topLevels != null) 'top_levels': topLevels,
      if (uploadedAt != null) 'uploaded_at': uploadedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SealedEnvelopesCompanion copyWith({
    Value<String>? batchId,
    Value<String>? projectId,
    Value<int>? createdAt,
    Value<int>? eventCount,
    Value<int>? payloadSize,
    Value<Uint8List>? wrappedKey,
    Value<Uint8List>? iv,
    Value<Uint8List>? tag,
    Value<Uint8List>? ciphertext,
    Value<int>? uploadState,
    Value<int>? attempts,
    Value<int?>? lastAttemptAt,
    Value<int>? seqMin,
    Value<int>? seqMax,
    Value<int>? minTs,
    Value<int>? maxTs,
    Value<String>? topLevels,
    Value<int?>? uploadedAt,
    Value<int>? rowid,
  }) {
    return SealedEnvelopesCompanion(
      batchId: batchId ?? this.batchId,
      projectId: projectId ?? this.projectId,
      createdAt: createdAt ?? this.createdAt,
      eventCount: eventCount ?? this.eventCount,
      payloadSize: payloadSize ?? this.payloadSize,
      wrappedKey: wrappedKey ?? this.wrappedKey,
      iv: iv ?? this.iv,
      tag: tag ?? this.tag,
      ciphertext: ciphertext ?? this.ciphertext,
      uploadState: uploadState ?? this.uploadState,
      attempts: attempts ?? this.attempts,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      seqMin: seqMin ?? this.seqMin,
      seqMax: seqMax ?? this.seqMax,
      minTs: minTs ?? this.minTs,
      maxTs: maxTs ?? this.maxTs,
      topLevels: topLevels ?? this.topLevels,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (eventCount.present) {
      map['event_count'] = Variable<int>(eventCount.value);
    }
    if (payloadSize.present) {
      map['payload_size'] = Variable<int>(payloadSize.value);
    }
    if (wrappedKey.present) {
      map['wrapped_key'] = Variable<Uint8List>(wrappedKey.value);
    }
    if (iv.present) {
      map['iv'] = Variable<Uint8List>(iv.value);
    }
    if (tag.present) {
      map['tag'] = Variable<Uint8List>(tag.value);
    }
    if (ciphertext.present) {
      map['ciphertext'] = Variable<Uint8List>(ciphertext.value);
    }
    if (uploadState.present) {
      map['upload_state'] = Variable<int>(uploadState.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<int>(lastAttemptAt.value);
    }
    if (seqMin.present) {
      map['seq_min'] = Variable<int>(seqMin.value);
    }
    if (seqMax.present) {
      map['seq_max'] = Variable<int>(seqMax.value);
    }
    if (minTs.present) {
      map['min_ts'] = Variable<int>(minTs.value);
    }
    if (maxTs.present) {
      map['max_ts'] = Variable<int>(maxTs.value);
    }
    if (topLevels.present) {
      map['top_levels'] = Variable<String>(topLevels.value);
    }
    if (uploadedAt.present) {
      map['uploaded_at'] = Variable<int>(uploadedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SealedEnvelopesCompanion(')
          ..write('batchId: $batchId, ')
          ..write('projectId: $projectId, ')
          ..write('createdAt: $createdAt, ')
          ..write('eventCount: $eventCount, ')
          ..write('payloadSize: $payloadSize, ')
          ..write('wrappedKey: $wrappedKey, ')
          ..write('iv: $iv, ')
          ..write('tag: $tag, ')
          ..write('ciphertext: $ciphertext, ')
          ..write('uploadState: $uploadState, ')
          ..write('attempts: $attempts, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('seqMin: $seqMin, ')
          ..write('seqMax: $seqMax, ')
          ..write('minTs: $minTs, ')
          ..write('maxTs: $maxTs, ')
          ..write('topLevels: $topLevels, ')
          ..write('uploadedAt: $uploadedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SealedMetaTable extends SealedMeta
    with TableInfo<$SealedMetaTable, MetaRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SealedMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sealed_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<MetaRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  MetaRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MetaRecord(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SealedMetaTable createAlias(String alias) {
    return $SealedMetaTable(attachedDatabase, alias);
  }
}

class MetaRecord extends DataClass implements Insertable<MetaRecord> {
  /// The key.
  final String key;

  /// The value.
  final String value;
  const MetaRecord({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SealedMetaCompanion toCompanion(bool nullToAbsent) {
    return SealedMetaCompanion(key: Value(key), value: Value(value));
  }

  factory MetaRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MetaRecord(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  MetaRecord copyWith({String? key, String? value}) =>
      MetaRecord(key: key ?? this.key, value: value ?? this.value);
  MetaRecord copyWithCompanion(SealedMetaCompanion data) {
    return MetaRecord(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MetaRecord(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MetaRecord &&
          other.key == this.key &&
          other.value == this.value);
}

class SealedMetaCompanion extends UpdateCompanion<MetaRecord> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SealedMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SealedMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<MetaRecord> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SealedMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SealedMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SealedMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$SealedDatabase extends GeneratedDatabase {
  _$SealedDatabase(QueryExecutor e) : super(e);
  $SealedDatabaseManager get managers => $SealedDatabaseManager(this);
  late final $SealedEnvelopesTable sealedEnvelopes = $SealedEnvelopesTable(
    this,
  );
  late final $SealedMetaTable sealedMeta = $SealedMetaTable(this);
  late final Index idxEnvCreated = Index(
    'idx_env_created',
    'CREATE INDEX idx_env_created ON sealed_envelopes (created_at)',
  );
  late final Index idxEnvState = Index(
    'idx_env_state',
    'CREATE INDEX idx_env_state ON sealed_envelopes (upload_state, created_at)',
  );
  late final Index idxEnvTsRange = Index(
    'idx_env_ts_range',
    'CREATE INDEX idx_env_ts_range ON sealed_envelopes (min_ts, max_ts)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sealedEnvelopes,
    sealedMeta,
    idxEnvCreated,
    idxEnvState,
    idxEnvTsRange,
  ];
}

typedef $$SealedEnvelopesTableCreateCompanionBuilder =
    SealedEnvelopesCompanion Function({
      required String batchId,
      required String projectId,
      required int createdAt,
      required int eventCount,
      required int payloadSize,
      required Uint8List wrappedKey,
      required Uint8List iv,
      required Uint8List tag,
      required Uint8List ciphertext,
      Value<int> uploadState,
      Value<int> attempts,
      Value<int?> lastAttemptAt,
      required int seqMin,
      required int seqMax,
      required int minTs,
      required int maxTs,
      required String topLevels,
      Value<int?> uploadedAt,
      Value<int> rowid,
    });
typedef $$SealedEnvelopesTableUpdateCompanionBuilder =
    SealedEnvelopesCompanion Function({
      Value<String> batchId,
      Value<String> projectId,
      Value<int> createdAt,
      Value<int> eventCount,
      Value<int> payloadSize,
      Value<Uint8List> wrappedKey,
      Value<Uint8List> iv,
      Value<Uint8List> tag,
      Value<Uint8List> ciphertext,
      Value<int> uploadState,
      Value<int> attempts,
      Value<int?> lastAttemptAt,
      Value<int> seqMin,
      Value<int> seqMax,
      Value<int> minTs,
      Value<int> maxTs,
      Value<String> topLevels,
      Value<int?> uploadedAt,
      Value<int> rowid,
    });

class $$SealedEnvelopesTableFilterComposer
    extends Composer<_$SealedDatabase, $SealedEnvelopesTable> {
  $$SealedEnvelopesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get eventCount => $composableBuilder(
    column: $table.eventCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get payloadSize => $composableBuilder(
    column: $table.payloadSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get wrappedKey => $composableBuilder(
    column: $table.wrappedKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get iv => $composableBuilder(
    column: $table.iv,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get ciphertext => $composableBuilder(
    column: $table.ciphertext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seqMin => $composableBuilder(
    column: $table.seqMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seqMax => $composableBuilder(
    column: $table.seqMax,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minTs => $composableBuilder(
    column: $table.minTs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxTs => $composableBuilder(
    column: $table.maxTs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topLevels => $composableBuilder(
    column: $table.topLevels,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SealedEnvelopesTableOrderingComposer
    extends Composer<_$SealedDatabase, $SealedEnvelopesTable> {
  $$SealedEnvelopesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get eventCount => $composableBuilder(
    column: $table.eventCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get payloadSize => $composableBuilder(
    column: $table.payloadSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get wrappedKey => $composableBuilder(
    column: $table.wrappedKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get iv => $composableBuilder(
    column: $table.iv,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get ciphertext => $composableBuilder(
    column: $table.ciphertext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seqMin => $composableBuilder(
    column: $table.seqMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seqMax => $composableBuilder(
    column: $table.seqMax,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minTs => $composableBuilder(
    column: $table.minTs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxTs => $composableBuilder(
    column: $table.maxTs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topLevels => $composableBuilder(
    column: $table.topLevels,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SealedEnvelopesTableAnnotationComposer
    extends Composer<_$SealedDatabase, $SealedEnvelopesTable> {
  $$SealedEnvelopesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get batchId =>
      $composableBuilder(column: $table.batchId, builder: (column) => column);

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get eventCount => $composableBuilder(
    column: $table.eventCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get payloadSize => $composableBuilder(
    column: $table.payloadSize,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get wrappedKey => $composableBuilder(
    column: $table.wrappedKey,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get iv =>
      $composableBuilder(column: $table.iv, builder: (column) => column);

  GeneratedColumn<Uint8List> get tag =>
      $composableBuilder(column: $table.tag, builder: (column) => column);

  GeneratedColumn<Uint8List> get ciphertext => $composableBuilder(
    column: $table.ciphertext,
    builder: (column) => column,
  );

  GeneratedColumn<int> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<int> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get seqMin =>
      $composableBuilder(column: $table.seqMin, builder: (column) => column);

  GeneratedColumn<int> get seqMax =>
      $composableBuilder(column: $table.seqMax, builder: (column) => column);

  GeneratedColumn<int> get minTs =>
      $composableBuilder(column: $table.minTs, builder: (column) => column);

  GeneratedColumn<int> get maxTs =>
      $composableBuilder(column: $table.maxTs, builder: (column) => column);

  GeneratedColumn<String> get topLevels =>
      $composableBuilder(column: $table.topLevels, builder: (column) => column);

  GeneratedColumn<int> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => column,
  );
}

class $$SealedEnvelopesTableTableManager
    extends
        RootTableManager<
          _$SealedDatabase,
          $SealedEnvelopesTable,
          EnvelopeRecord,
          $$SealedEnvelopesTableFilterComposer,
          $$SealedEnvelopesTableOrderingComposer,
          $$SealedEnvelopesTableAnnotationComposer,
          $$SealedEnvelopesTableCreateCompanionBuilder,
          $$SealedEnvelopesTableUpdateCompanionBuilder,
          (
            EnvelopeRecord,
            BaseReferences<
              _$SealedDatabase,
              $SealedEnvelopesTable,
              EnvelopeRecord
            >,
          ),
          EnvelopeRecord,
          PrefetchHooks Function()
        > {
  $$SealedEnvelopesTableTableManager(
    _$SealedDatabase db,
    $SealedEnvelopesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SealedEnvelopesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SealedEnvelopesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SealedEnvelopesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> batchId = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> eventCount = const Value.absent(),
                Value<int> payloadSize = const Value.absent(),
                Value<Uint8List> wrappedKey = const Value.absent(),
                Value<Uint8List> iv = const Value.absent(),
                Value<Uint8List> tag = const Value.absent(),
                Value<Uint8List> ciphertext = const Value.absent(),
                Value<int> uploadState = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int?> lastAttemptAt = const Value.absent(),
                Value<int> seqMin = const Value.absent(),
                Value<int> seqMax = const Value.absent(),
                Value<int> minTs = const Value.absent(),
                Value<int> maxTs = const Value.absent(),
                Value<String> topLevels = const Value.absent(),
                Value<int?> uploadedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SealedEnvelopesCompanion(
                batchId: batchId,
                projectId: projectId,
                createdAt: createdAt,
                eventCount: eventCount,
                payloadSize: payloadSize,
                wrappedKey: wrappedKey,
                iv: iv,
                tag: tag,
                ciphertext: ciphertext,
                uploadState: uploadState,
                attempts: attempts,
                lastAttemptAt: lastAttemptAt,
                seqMin: seqMin,
                seqMax: seqMax,
                minTs: minTs,
                maxTs: maxTs,
                topLevels: topLevels,
                uploadedAt: uploadedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String batchId,
                required String projectId,
                required int createdAt,
                required int eventCount,
                required int payloadSize,
                required Uint8List wrappedKey,
                required Uint8List iv,
                required Uint8List tag,
                required Uint8List ciphertext,
                Value<int> uploadState = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int?> lastAttemptAt = const Value.absent(),
                required int seqMin,
                required int seqMax,
                required int minTs,
                required int maxTs,
                required String topLevels,
                Value<int?> uploadedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SealedEnvelopesCompanion.insert(
                batchId: batchId,
                projectId: projectId,
                createdAt: createdAt,
                eventCount: eventCount,
                payloadSize: payloadSize,
                wrappedKey: wrappedKey,
                iv: iv,
                tag: tag,
                ciphertext: ciphertext,
                uploadState: uploadState,
                attempts: attempts,
                lastAttemptAt: lastAttemptAt,
                seqMin: seqMin,
                seqMax: seqMax,
                minTs: minTs,
                maxTs: maxTs,
                topLevels: topLevels,
                uploadedAt: uploadedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SealedEnvelopesTable, EnvelopeRecord>(table),
                  BaseReferences<
                    _$SealedDatabase,
                    $SealedEnvelopesTable,
                    EnvelopeRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SealedEnvelopesTableProcessedTableManager =
    ProcessedTableManager<
      _$SealedDatabase,
      $SealedEnvelopesTable,
      EnvelopeRecord,
      $$SealedEnvelopesTableFilterComposer,
      $$SealedEnvelopesTableOrderingComposer,
      $$SealedEnvelopesTableAnnotationComposer,
      $$SealedEnvelopesTableCreateCompanionBuilder,
      $$SealedEnvelopesTableUpdateCompanionBuilder,
      (
        EnvelopeRecord,
        BaseReferences<_$SealedDatabase, $SealedEnvelopesTable, EnvelopeRecord>,
      ),
      EnvelopeRecord,
      PrefetchHooks Function()
    >;
typedef $$SealedMetaTableCreateCompanionBuilder =
    SealedMetaCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SealedMetaTableUpdateCompanionBuilder =
    SealedMetaCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SealedMetaTableFilterComposer
    extends Composer<_$SealedDatabase, $SealedMetaTable> {
  $$SealedMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SealedMetaTableOrderingComposer
    extends Composer<_$SealedDatabase, $SealedMetaTable> {
  $$SealedMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SealedMetaTableAnnotationComposer
    extends Composer<_$SealedDatabase, $SealedMetaTable> {
  $$SealedMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SealedMetaTableTableManager
    extends
        RootTableManager<
          _$SealedDatabase,
          $SealedMetaTable,
          MetaRecord,
          $$SealedMetaTableFilterComposer,
          $$SealedMetaTableOrderingComposer,
          $$SealedMetaTableAnnotationComposer,
          $$SealedMetaTableCreateCompanionBuilder,
          $$SealedMetaTableUpdateCompanionBuilder,
          (
            MetaRecord,
            BaseReferences<_$SealedDatabase, $SealedMetaTable, MetaRecord>,
          ),
          MetaRecord,
          PrefetchHooks Function()
        > {
  $$SealedMetaTableTableManager(_$SealedDatabase db, $SealedMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SealedMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SealedMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SealedMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SealedMetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SealedMetaCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SealedMetaTable, MetaRecord>(table),
                  BaseReferences<
                    _$SealedDatabase,
                    $SealedMetaTable,
                    MetaRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SealedMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$SealedDatabase,
      $SealedMetaTable,
      MetaRecord,
      $$SealedMetaTableFilterComposer,
      $$SealedMetaTableOrderingComposer,
      $$SealedMetaTableAnnotationComposer,
      $$SealedMetaTableCreateCompanionBuilder,
      $$SealedMetaTableUpdateCompanionBuilder,
      (
        MetaRecord,
        BaseReferences<_$SealedDatabase, $SealedMetaTable, MetaRecord>,
      ),
      MetaRecord,
      PrefetchHooks Function()
    >;

class $SealedDatabaseManager {
  final _$SealedDatabase _db;
  $SealedDatabaseManager(this._db);
  $$SealedEnvelopesTableTableManager get sealedEnvelopes =>
      $$SealedEnvelopesTableTableManager(_db, _db.sealedEnvelopes);
  $$SealedMetaTableTableManager get sealedMeta =>
      $$SealedMetaTableTableManager(_db, _db.sealedMeta);
}
