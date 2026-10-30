import 'package:drift/drift.dart';

part 'database.g.dart';

/// Sealed envelopes: encrypted blobs plus clear index columns.
///
/// No column holds plaintext. Retention and upload scheduling read only the
/// clear columns (`created_at`, `event_count`, `upload_state`, `min_ts`,
/// `max_ts`, `top_levels`) and never decrypt.
@DataClassName('EnvelopeRecord')
@TableIndex(name: 'idx_env_created', columns: {#createdAt})
@TableIndex(name: 'idx_env_state', columns: {#uploadState, #createdAt})
@TableIndex(name: 'idx_env_ts_range', columns: {#minTs, #maxTs})
class SealedEnvelopes extends Table {
  /// uuid-v4 of the batch.
  TextColumn get batchId => text()();

  /// Project the batch belongs to.
  TextColumn get projectId => text()();

  /// Creation time, epoch milliseconds.
  IntColumn get createdAt => integer()();

  /// Events inside.
  IntColumn get eventCount => integer()();

  /// Plaintext JSON size in bytes, before encryption.
  IntColumn get payloadSize => integer()();

  /// AES key wrapped with the project's RSA public key.
  BlobColumn get wrappedKey => blob()();

  /// AES-GCM nonce.
  BlobColumn get iv => blob()();

  /// AES-GCM tag.
  BlobColumn get tag => blob()();

  /// Encrypted JSON array of events.
  BlobColumn get ciphertext => blob()();

  /// 0 pending, 1 dead letter.
  IntColumn get uploadState => integer().withDefault(const Constant(0))();

  /// Failed upload attempts.
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Time of the last attempt, epoch milliseconds.
  IntColumn get lastAttemptAt => integer().nullable()();

  /// Smallest event sequence number inside.
  IntColumn get seqMin => integer()();

  /// Largest event sequence number inside.
  IntColumn get seqMax => integer()();

  /// Earliest event time inside, epoch milliseconds.
  IntColumn get minTs => integer()();

  /// Latest event time inside, epoch milliseconds.
  IntColumn get maxTs => integer()();

  /// Distinct levels inside, comma separated, in severity order.
  TextColumn get topLevels => text()();

  /// Set once the server acknowledged the batch, until the row is deleted.
  IntColumn get uploadedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {batchId};
}

/// Small non-sensitive bookkeeping values, such as the sequence high-water
/// mark. Holds no log content.
@DataClassName('MetaRecord')
class SealedMeta extends Table {
  /// The key.
  TextColumn get key => text()();

  /// The value.
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// The local SQLite database.
@DriftDatabase(tables: [SealedEnvelopes, SealedMeta])
class SealedDatabase extends _$SealedDatabase {
  /// Opens the database on [executor].
  SealedDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Version 1 is the first schema. Additive migrations land here.
    },
  );
}
