import 'dart:async';
import 'dart:developer' as developer;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/network/backend_api_client.dart';
import '../../../core/network/backend_entity_id_registry.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../../../models/sync/sync_status.dart';
import '../../../repositories/sync_repository.dart';
import '../../../services/sync/sync_queue_service.dart';
import '../domain/seller.dart';

class SellerRepository implements SyncRepository {
  SellerRepository({
    AppDatabase? database,
    SyncQueueService? syncQueueService,
    BackendApiClient? apiClient,
  }) : _appDatabase = database ?? AppDatabase.instance,
       _syncQueueService = syncQueueService ?? SyncQueueService.instance,
       _apiClient = apiClient ?? BackendApiClient() {
    _syncQueueService.registerRepository(this);
  }

  final AppDatabase _appDatabase;
  final SyncQueueService _syncQueueService;
  final BackendApiClient _apiClient;
  final BackendEntityIdRegistry _idRegistry = BackendEntityIdRegistry.instance;

  bool get _shouldRunBackgroundSync =>
      identical(_appDatabase, AppDatabase.instance);
  bool get _useBackendMode => false;

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
    if (_useBackendMode) {
      return _fetchAllFromBackend();
    }

    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.sellersTable,
      where: 'deleted_at IS NULL',
      orderBy: 'nombre ASC',
    );

    return rows.map((row) => Seller.fromMap(row)).toList();
  }

  Future<Seller?> getById(int id) async {
    if (_useBackendMode) {
      final sellers = await _fetchAllFromBackend();
      for (final seller in sellers) {
        if (seller.id == id) {
          return seller;
        }
      }
      return null;
    }

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
      if (_useBackendMode) {
        final created = await _apiClient.post(
          '/sellers',
          body: _toBackendPayload(seller),
        );
        final mapped = _sellerFromBackend(
          (created as Map).map((key, value) => MapEntry(key.toString(), value)),
        );
        return mapped.id ?? 0;
      }

      final db = await _appDatabase.database;
      final duplicateId = await _findActiveSellerIdByDocumentId(
        seller.documentId,
      );
      if (duplicateId != null) {
        throw StateError(
          'Ya existe un vendedor activo con esta cédula. Verifica los datos antes de continuar.',
        );
      }

      // Anonimizar cualquier registro eliminado que aún conserve la cédula
      // original, para evitar el UNIQUE constraint de SQLite en el INSERT.
      await db.rawUpdate(
        "UPDATE ${DatabaseSchema.sellersTable} "
        "SET cedula = '__DELETED__' || CAST(id AS TEXT) "
        'WHERE deleted_at IS NOT NULL '
        'AND TRIM(cedula) = ?',
        [seller.documentId],
      );

      final id = await db.insert(DatabaseSchema.sellersTable, {
        ...seller.toMap(),
        'sync_id': _newSyncId(),
        'id_local': null,
        'id_remote': null,
        'last_modified_local': DateTime.now().toIso8601String(),
        'deleted_at': null,
        'sync_status': DatabaseSchema.syncStatusPendingCreate,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      _log('SELLER LOCAL CREATED -> id=$id documentId=${seller.documentId}');
      _scheduleBackgroundSync('create-seller:$id');
      // Garantizar sync inmediato tras crear vendedor para todos los usuarios
      _scheduleExplicitSync('create-seller:$id');
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
      if (_useBackendMode) {
        final remoteId = _idRegistry.resolveRemoteId('sellers', seller.id);
        if (remoteId == null || remoteId.isEmpty) {
          throw const BackendApiException(
            'No se pudo identificar el vendedor remoto para actualizarlo.',
          );
        }
        await _apiClient.patch(
          '/sellers/$remoteId',
          body: _toBackendPayload(seller),
        );
        return;
      }

      if (seller.id == null) {
        throw ArgumentError('Seller must have an ID to update');
      }

      final db = await _appDatabase.database;
      final duplicateId = await _findActiveSellerIdByDocumentId(
        seller.documentId,
        excludeId: seller.id,
      );
      if (duplicateId != null) {
        throw StateError(
          'Ya existe un vendedor activo con esta cédula. Verifica los datos antes de continuar.',
        );
      }

      await db.update(
        DatabaseSchema.sellersTable,
        {
          ...seller.toMap(),
          'sync_status': DatabaseSchema.syncStatusPendingUpdate,
          'last_modified_local': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [seller.id],
      );
      _log(
        'SELLER LOCAL UPDATED -> id=${seller.id} documentId=${seller.documentId}',
      );
      _scheduleBackgroundSync('update-seller:${seller.id}');
      // Garantizar sync inmediato tras actualizar vendedor para todos los usuarios
      _scheduleExplicitSync('update-seller:${seller.id}');
    } catch (error, stackTrace) {
      print('💥 ERROR SQLITE: $error');
      print(stackTrace);
      _log('SELLER UPDATE ERROR', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> delete(int id) async {
    try {
      if (_useBackendMode) {
        final remoteId = _idRegistry.resolveRemoteId('sellers', id);
        if (remoteId == null || remoteId.isEmpty) {
          throw const BackendApiException(
            'No se pudo identificar el vendedor remoto para eliminarlo.',
          );
        }
        await _apiClient.delete('/sellers/$remoteId');
        return;
      }

      final db = await _appDatabase.database;

      final sellerRows = await db.query(
        DatabaseSchema.sellersTable,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (sellerRows.isEmpty) {
        return;
      }

      final sellerRow = sellerRows.first;
      final deletedAt = DateTime.now().toIso8601String();
      final payload = {
        'id': sellerRow['id'],
        'sync_id': sellerRow['sync_id'],
        'version': ((sellerRow['version'] as int?) ?? 1) + 1,
        'name': sellerRow['nombre'],
        'full_name': sellerRow['nombre'],
        'document_id': sellerRow['cedula'],
        'phone': sellerRow['telefono'],
        'created_at': sellerRow['fecha_creacion'],
        'updated_at': deletedAt,
        'deleted_at': deletedAt,
        'sync_status': DatabaseSchema.syncStatusPendingDelete,
      };

      final currentDocument = (sellerRow['cedula']?.toString() ?? '');
      final syncId = (sellerRow['sync_id'] as String?)?.trim();
      final deletedDocument = _deletedDocumentPlaceholder(currentDocument, id);

      await db.update(
        DatabaseSchema.sellersTable,
        {
          'cedula': deletedDocument,
          'deleted_at': deletedAt,
          'fecha_actualizacion': deletedAt,
          'sync_status': DatabaseSchema.syncStatusPendingDelete,
          'last_modified_local': deletedAt,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (syncId != null && syncId.isNotEmpty) {
        await _syncQueueService.enqueueDelete(
          scope: 'sellers',
          recordSyncId: syncId,
          payload: payload,
        );
      }
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
    if (!_shouldRunBackgroundSync) {
      return;
    }
    unawaited(_runBackgroundSync(operationLabel));
  }

  void _scheduleExplicitSync(String operationLabel) {
    if (!_shouldRunBackgroundSync) {
      return;
    }
    // Intenta sincronizar inmediatamente sin esperar (fire-and-forget)
    // para garantizar que cambios se suban a la nube SIEMPRE, no solo en background
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
    if (_useBackendMode) {
      return _fetchAllFromBackend(query: query);
    }

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
      where: 'sync_status IN (?, ?, ?, ?, ?)',
      whereArgs: [
        SyncStatus.pending.storageValue,
        DatabaseSchema.syncStatusPendingCreate,
        DatabaseSchema.syncStatusPendingUpdate,
        DatabaseSchema.syncStatusPendingDelete,
        DatabaseSchema.syncStatusFailed,
      ],
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
        final localRow = existing.isEmpty ? null : existing.first;
        final localDeletedAt = localRow?['deleted_at']?.toString().trim();
        final remoteDeletedAt = record['deleted_at']?.toString().trim();
        if (localRow != null &&
            localDeletedAt != null &&
            localDeletedAt.isNotEmpty &&
            (remoteDeletedAt == null || remoteDeletedAt.isEmpty)) {
          continue;
        }

        if (_shouldKeepLocal(existing, record)) {
          continue;
        }

        final values = {
          'sync_id': syncId,
          'id_remote': record['id']?.toString().trim(),
          'id_local': existing.isEmpty ? null : existing.first['id'],
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
          'last_modified_remote':
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
    final now = DateTime.now().toIso8601String();
    await db.rawUpdate(
      'UPDATE ${DatabaseSchema.sellersTable} '
      'SET sync_status = ?, fecha_actualizacion = COALESCE(fecha_actualizacion, ?), '
      'last_modified_local = COALESCE(last_modified_local, ?) '
      'WHERE sync_id IN ($placeholders)',
      [status, now, now, ...ids],
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
    final localSyncStatus = (local['sync_status'] as String? ?? '')
        .trim()
        .toLowerCase();
    final localPending = DatabaseSchema.writableSyncStatuses.contains(
      localSyncStatus,
    );
    if (!localPending) {
      return false;
    }

    final localVersion = _readVersion(local);
    final remoteVersion = _readVersion(remoteRecord);
    if (localVersion > remoteVersion) {
      return true;
    }
    if (localVersion < remoteVersion) {
      return false;
    }

    final localUpdated = _parseDate(
      local['last_modified_local']?.toString() ??
          local['fecha_actualizacion']?.toString(),
    );
    final remoteUpdated = _parseDate(
      remoteRecord['last_modified_remote']?.toString() ??
          remoteRecord['updated_at']?.toString(),
    );

    return localUpdated != null &&
        remoteUpdated != null &&
        localUpdated.isAfter(remoteUpdated);
  }

  DateTime? _parseDate(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return DateTime.tryParse(normalized);
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

  Future<List<Seller>> _fetchAllFromBackend({String query = ''}) async {
    final response = await _apiClient.get(
      '/sellers',
      queryParameters: {
        'page': '1',
        'limit': '100',
        if (query.trim().isNotEmpty) 'search': query.trim(),
      },
    );
    final payload = response is Map<String, dynamic>
        ? response
        : (response as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          );
    final items = (payload['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map(
          (item) => _sellerFromBackend(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }

  Seller _sellerFromBackend(Map<String, dynamic> item) {
    final remoteId = item['id']?.toString().trim() ?? '';
    final localId = _idRegistry.register('sellers', remoteId);
    return Seller(
      id: localId,
      name: item['name']?.toString().trim() ?? '',
      phone: item['phone']?.toString().trim() ?? '',
      documentId: item['documentId']?.toString().trim() ?? '',
      createdAt:
          DateTime.tryParse(item['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(item['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> _toBackendPayload(Seller seller) {
    return {
      'name': seller.name.trim(),
      'documentId': seller.documentId.trim().isEmpty
          ? null
          : seller.documentId.trim(),
      'phone': seller.phone.trim().isEmpty ? null : seller.phone.trim(),
    };
  }

  Future<int?> _findActiveSellerIdByDocumentId(
    String documentId, {
    int? excludeId,
  }) async {
    final normalized = documentId.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final db = await _appDatabase.database;
    final where = StringBuffer('deleted_at IS NULL AND TRIM(cedula) = ?');
    final whereArgs = <Object>[normalized];
    if (excludeId != null) {
      where.write(' AND id <> ?');
      whereArgs.add(excludeId);
    }

    final rows = await db.query(
      DatabaseSchema.sellersTable,
      columns: ['id'],
      where: where.toString(),
      whereArgs: whereArgs,
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final id = rows.first['id'];
    if (id is int) {
      return id;
    }
    if (id is num) {
      return id.toInt();
    }
    return int.tryParse(id?.toString() ?? '');
  }

  String _deletedDocumentPlaceholder(String documentId, int id) {
    final normalized = documentId.trim();
    if (normalized.startsWith('__DELETED__')) {
      return normalized;
    }
    return '__DELETED__$id';
  }
}
