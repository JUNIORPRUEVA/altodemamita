import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../../../core/system/system_config_service.dart';
import '../../../models/sync/sync_status.dart';
import '../../../repositories/sync_repository.dart';
import '../../../services/sync/sync_queue_service.dart';
import '../domain/client.dart';

class ClientRepository implements SyncRepository {
  ClientRepository({
    AppDatabase? appDatabase,
    SyncQueueService? syncQueueService,
  }) : _appDatabase = appDatabase ?? AppDatabase.instance,
       _syncQueueService = syncQueueService ?? SyncQueueService.instance {
    _syncQueueService.registerRepository(this);
  }

  final AppDatabase _appDatabase;
  final SyncQueueService _syncQueueService;

  @override
  String get scope => 'clients';

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/changes';

  Future<List<Client>> fetchAll({String query = ''}) async {
    final db = await _appDatabase.database;
    final normalizedQuery = query.trim();
    final rows = await db.query(
      DatabaseSchema.clientsTable,
      where: normalizedQuery.isEmpty
          ? 'deleted_at IS NULL'
          : 'deleted_at IS NULL AND (nombre LIKE ? OR cedula LIKE ? OR telefono LIKE ?)',
      whereArgs: normalizedQuery.isEmpty
          ? null
          : List.filled(3, '%$normalizedQuery%'),
      orderBy: 'nombre COLLATE NOCASE ASC',
    );

    return rows.map(Client.fromMap).toList();
  }

  Future<int> countAll() async {
    final db = await _appDatabase.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) FROM ${DatabaseSchema.clientsTable} WHERE deleted_at IS NULL',
    );
    return _readCount(result);
  }

  Future<Client?> findByDocumentId(String documentId) async {
    final normalizedDocumentId = documentId.trim();
    if (normalizedDocumentId.isEmpty) {
      return null;
    }

    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.clientsTable,
      where: 'cedula = ? AND deleted_at IS NULL',
      whereArgs: [normalizedDocumentId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return Client.fromMap(rows.first);
  }

  Future<void> save(Client client) async {
    SystemConfigService.instance.ensureWritable();

    final db = await _appDatabase.database;
    final now = DateTime.now();
    final normalizedClient = client.copyWith(
      syncId: _normalizeSyncId(client.syncId),
      createdAt: client.id == null ? now : client.createdAt,
      updatedAt: now,
      clearDeletedAt: true,
      syncStatus: SyncStatus.pending,
    );

    if (normalizedClient.id == null) {
      await db.insert(
        DatabaseSchema.clientsTable,
        normalizedClient.toMap()..remove('id'),
      );
      await _syncQueueService.refreshScope(scope);
      return;
    }

    await db.update(
      DatabaseSchema.clientsTable,
      normalizedClient.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [normalizedClient.id],
    );
    await _syncQueueService.refreshScope(scope);
  }

  Future<void> delete(int id) async {
    SystemConfigService.instance.ensureWritable();

    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.clientsTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return;
    }

    final existing = Client.fromMap(rows.first);
    final now = DateTime.now();
    final deletedClient = existing.copyWith(
      updatedAt: now,
      deletedAt: now,
      syncStatus: SyncStatus.pending,
    );
    await db.update(
      DatabaseSchema.clientsTable,
      deletedClient.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [id],
    );
    await _syncQueueService.refreshScope(scope);
  }

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.clientsTable,
      where: 'sync_status = ?',
      whereArgs: [SyncStatus.pending.storageValue],
      orderBy: 'fecha_actualizacion ASC',
    );

    return rows.map((row) => Client.fromMap(row).toSyncPayload()).toList();
  }

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) async {
    final normalizedIds = syncIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedIds.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    final placeholders = List.filled(normalizedIds.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE ${DatabaseSchema.clientsTable} '
      'SET sync_status = ? '
      'WHERE sync_id IN ($placeholders)',
      [SyncStatus.synced.storageValue, ...normalizedIds],
    );
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) async {
    final normalizedIds = syncIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (normalizedIds.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    final placeholders = List.filled(normalizedIds.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE ${DatabaseSchema.clientsTable} '
      'SET sync_status = ? '
      'WHERE sync_id IN ($placeholders)',
      [SyncStatus.conflict.storageValue, ...normalizedIds],
    );
  }

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {
    if (records.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      for (final record in records) {
        final remoteClient = Client.fromSyncMap(record).copyWith(
          syncId: _normalizeSyncId(record['sync_id']?.toString()),
          syncStatus: SyncStatus.synced,
        );
        final existingRows = await txn.query(
          DatabaseSchema.clientsTable,
          where: 'sync_id = ?',
          whereArgs: [remoteClient.syncId],
          limit: 1,
        );

        if (existingRows.isEmpty) {
          await txn.insert(DatabaseSchema.clientsTable, remoteClient.toMap());
          continue;
        }

        final localClient = Client.fromMap(existingRows.first);
        final localHasPendingChanges =
            (localClient.syncStatus.isPending ||
                localClient.syncStatus.isConflict) &&
            localClient.version >= remoteClient.version &&
            localClient.updatedAt.isAfter(remoteClient.updatedAt);
        if (localHasPendingChanges) {
          continue;
        }

        await txn.update(
          DatabaseSchema.clientsTable,
          remoteClient.toMap()..remove('id'),
          where: 'sync_id = ?',
          whereArgs: [remoteClient.syncId],
        );
      }
    });
  }

  int _readCount(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) {
      return 0;
    }

    final value = rows.first.values.first;
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString()) ?? 0;
  }

  String _normalizeSyncId(String? currentSyncId) {
    final normalized = currentSyncId?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return normalized;
    }
    return 'client-${DateTime.now().microsecondsSinceEpoch}';
  }
}
