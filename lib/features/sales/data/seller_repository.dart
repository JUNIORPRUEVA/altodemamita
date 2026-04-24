import 'dart:async';
import 'dart:developer' as developer;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../../../core/system/system_config_service.dart';
import '../../../models/sync/sync_status.dart';
import '../../../repositories/sync_repository.dart';
import '../../../services/sync/sync_queue_service.dart';
import '../domain/seller.dart';

class SellerRepository implements SyncRepository {
  SellerRepository({AppDatabase? database, SyncQueueService? syncQueueService})
    : _appDatabase = database ?? AppDatabase.instance,
      _syncQueueService = syncQueueService ?? SyncQueueService.instance {
    _syncQueueService.registerRepository(this);
  }

  final AppDatabase _appDatabase;
  final SyncQueueService _syncQueueService;

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: 'SistemaSolares.SellerRepository',
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  String get scope => 'sellers';

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/changes';

  Future<List<Seller>> getAll() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.sellersTable,
      where: 'deleted_at IS NULL',
      orderBy: 'nombre ASC',
    );

    return rows.map((row) => Seller.fromMap(row)).toList();
  }

  Future<Seller?> getById(int id) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.sellersTable,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return Seller.fromMap(rows.first);
  }

  Future<int> insert(Seller seller) async {
    try {
      SystemConfigService.instance.ensureWritable();

      final db = await _appDatabase.database;
      final id = await db.insert(DatabaseSchema.sellersTable, {
        ...seller.toMap(),
        'sync_id': _newSyncId(),
        'deleted_at': null,
        'sync_status': SyncStatus.pending.storageValue,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      _log('SELLER LOCAL CREATED -> id=$id documentId=${seller.documentId}');
      _scheduleBackgroundSync('create-seller:$id');
      return id;
    } catch (error, stackTrace) {
      print('💥 ERROR SQLITE: $error');
      print(stackTrace);
      _log('SELLER INSERT ERROR', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> update(Seller seller) async {
    try {
      SystemConfigService.instance.ensureWritable();

      if (seller.id == null) {
        throw ArgumentError('Seller must have an ID to update');
      }

      final db = await _appDatabase.database;
      await db.update(
        DatabaseSchema.sellersTable,
        {...seller.toMap(), 'sync_status': SyncStatus.pending.storageValue},
        where: 'id = ?',
        whereArgs: [seller.id],
      );
      _log(
        'SELLER LOCAL UPDATED -> id=${seller.id} documentId=${seller.documentId}',
      );
      _scheduleBackgroundSync('update-seller:${seller.id}');
    } catch (error, stackTrace) {
      print('💥 ERROR SQLITE: $error');
      print(stackTrace);
      _log('SELLER UPDATE ERROR', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> delete(int id) async {
    try {
      SystemConfigService.instance.ensureWritable();

      final db = await _appDatabase.database;
      await db.update(
        DatabaseSchema.sellersTable,
        {
          'deleted_at': DateTime.now().toIso8601String(),
          'sync_status': SyncStatus.pending.storageValue,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      _log('SELLER LOCAL DELETED -> id=$id');
      _scheduleBackgroundSync('delete-seller:$id');
    } catch (error, stackTrace) {
      print('💥 ERROR SQLITE: $error');
      print(stackTrace);
      _log('SELLER DELETE ERROR', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  void _scheduleBackgroundSync(String operationLabel) {
    unawaited(_runBackgroundSync(operationLabel));
  }

  Future<void> _runBackgroundSync(String operationLabel) async {
    _log('SELLER SYNC ATTEMPT -> operation=$operationLabel');
    try {
      await _syncQueueService.refreshScope(scope);
      final processed = await _syncQueueService.processQueue(
        includeDeferred: true,
      );
      _log(
        'SELLER SYNC RESULT -> operation=$operationLabel processed=$processed',
      );
    } catch (error, stackTrace) {
      _log(
        'SELLER SYNC ERROR -> operation=$operationLabel',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<List<Seller>> search(String query) async {
    final db = await _appDatabase.database;
    final normalizedQuery = '%${query.toLowerCase()}%';

    final rows = await db.query(
      DatabaseSchema.sellersTable,
      where:
          'deleted_at IS NULL AND (LOWER(nombre) LIKE ? OR LOWER(cedula) LIKE ? OR LOWER(telefono) LIKE ?)',
      whereArgs: [normalizedQuery, normalizedQuery, normalizedQuery],
      orderBy: 'nombre ASC',
    );

    return rows.map((row) => Seller.fromMap(row)).toList();
  }

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.sellersTable,
      where: 'sync_status = ?',
      whereArgs: [SyncStatus.pending.storageValue],
      orderBy: 'fecha_actualizacion ASC',
    );

    return rows
        .map((row) {
          return {
            'id': row['id'],
            'sync_id': row['sync_id'],
            'version': 1,
            'name': row['nombre'],
            'full_name': row['nombre'],
            'document_id': row['cedula'],
            'phone': row['telefono'],
            'created_at': row['fecha_creacion'],
            'updated_at': row['fecha_actualizacion'],
            'deleted_at': row['deleted_at'],
            'sync_status': row['sync_status'],
          };
        })
        .toList(growable: false);
  }

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) {
    return _mark(syncIds, SyncStatus.synced.storageValue);
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) {
    return _mark(syncIds, SyncStatus.conflict.storageValue);
  }

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {
    if (records.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      for (final record in records) {
        final syncId = (record['sync_id']?.toString() ?? '').trim();
        if (syncId.isEmpty) {
          continue;
        }

        final existing = await txn.query(
          DatabaseSchema.sellersTable,
          where: 'sync_id = ?',
          whereArgs: [syncId],
          limit: 1,
        );

        if (_shouldKeepLocal(existing, record)) {
          continue;
        }

        final values = {
          'sync_id': syncId,
          'version': _readVersion(record),
          'nombre':
              record['name']?.toString() ??
              record['full_name']?.toString() ??
              '',
          'cedula': record['document_id']?.toString() ?? '',
          'telefono': record['phone']?.toString() ?? '',
          'fecha_creacion':
              record['created_at']?.toString() ??
              DateTime.now().toIso8601String(),
          'fecha_actualizacion':
              record['updated_at']?.toString() ??
              DateTime.now().toIso8601String(),
          'deleted_at': record['deleted_at']?.toString(),
          'sync_status': SyncStatus.synced.storageValue,
        };

        if (existing.isEmpty) {
          await txn.insert(DatabaseSchema.sellersTable, values);
        } else {
          await txn.update(
            DatabaseSchema.sellersTable,
            values,
            where: 'sync_id = ?',
            whereArgs: [syncId],
          );
        }
      }
    });
  }

  Future<void> _mark(Iterable<String> syncIds, String status) async {
    final ids = syncIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE ${DatabaseSchema.sellersTable} SET sync_status = ? WHERE sync_id IN ($placeholders)',
      [status, ...ids],
    );
  }

  String _newSyncId() => 'seller-${DateTime.now().microsecondsSinceEpoch}';

  bool _shouldKeepLocal(
    List<Map<String, Object?>> existingRows,
    Map<String, dynamic> remoteRecord,
  ) {
    if (existingRows.isEmpty) {
      return false;
    }

    final local = existingRows.first;
    final localPending =
        (local['sync_status'] as String? ?? '') ==
            SyncStatus.pending.storageValue ||
        (local['sync_status'] as String? ?? '') ==
            SyncStatus.conflict.storageValue;
    final localVersion = _readVersion(local);
    final remoteVersion = _readVersion(remoteRecord);
    final localUpdated = DateTime.tryParse(
      local['fecha_actualizacion']?.toString() ?? '',
    );
    final remoteUpdated = DateTime.tryParse(
      remoteRecord['updated_at']?.toString() ?? '',
    );

    return localPending &&
        ((localVersion > remoteVersion) ||
            (localVersion >= remoteVersion &&
                localUpdated != null &&
                remoteUpdated != null &&
                localUpdated.isAfter(remoteUpdated)));
  }

  int _readVersion(Map<Object?, Object?> map) {
    final value = map['version'];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 1;
  }
}
