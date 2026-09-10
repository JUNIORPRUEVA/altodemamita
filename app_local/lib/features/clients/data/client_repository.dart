import 'dart:async';
import 'dart:developer' as developer;

import '../../../core/network/backend_api_client.dart';
import '../../../core/network/backend_entity_id_registry.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../../../core/cloud_foundation/list_snapshot_store.dart';
import '../../../core/config/app_flags.dart';
import '../../../core/errors/active_sales_block_delete_exception.dart';
import '../../../core/system/system_config_service.dart';
import '../../../core/utils/client_data_guard.dart';
import '../../../models/sync/sync_status.dart';
import '../../../repositories/sync_repository.dart';
import '../../../services/sync/sync_queue_service.dart';
import '../domain/client.dart';

class ClientRepository implements SyncRepository {
  ClientRepository({
    AppDatabase? appDatabase,
    SyncQueueService? syncQueueService,
    BackendApiClient? apiClient,
    SystemConfigService? systemConfigService,
  }) : _appDatabase = appDatabase ?? AppDatabase.instance,
       _syncQueueService = syncQueueService ?? SyncQueueService.instance,
       _apiClient = apiClient ?? BackendApiClient(),
       _systemConfigService =
           systemConfigService ?? SystemConfigService.instance {
    _syncQueueService.registerRepository(this);
  }

  final AppDatabase _appDatabase;
  final SyncQueueService _syncQueueService;
  final BackendApiClient _apiClient;
  final SystemConfigService _systemConfigService;
  final BackendEntityIdRegistry _idRegistry = BackendEntityIdRegistry.instance;
  late final ListSnapshotStore _listSnapshot = ListSnapshotStore(
    _appDatabase,
    entity: 'clients',
  );

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: 'SistemaSolares.ClientRepository',
      error: error,
      stackTrace: stackTrace,
    );
  }

  bool get _enforceProductionGuards =>
      isProductionMode && identical(_appDatabase, AppDatabase.instance);
  bool get _shouldRunBackgroundSync =>
      identical(_appDatabase, AppDatabase.instance);
  bool get _useBackendMode =>
      cloudCutoverMode.usesAuthoritativeBusinessWrites;

  @override
  String get scope => 'clients';

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/changes';

  Future<List<Client>> fetchAll({String query = ''}) async {
    if (_useBackendMode) {
      return _fetchAllFromBackend(query: query);
    }

    final db = await _appDatabase.database;
    final normalizedQuery = query.trim();
    final rows = normalizedQuery.isEmpty
        ? await db.query(
            DatabaseSchema.clientsTable,
            where: 'deleted_at IS NULL',
            orderBy: 'nombre COLLATE NOCASE ASC',
          )
        : await db.rawQuery(
            '''
            SELECT *
            FROM ${DatabaseSchema.clientsTable}
            WHERE deleted_at IS NULL
              AND (
                nombre LIKE ?
                OR cedula LIKE ?
                OR telefono LIKE ?
                OR direccion LIKE ?
                OR (? <> '' AND ${_normalizedPhoneSql('telefono')} LIKE ?)
              )
            ORDER BY nombre COLLATE NOCASE ASC
            ''',
            [
              '%$normalizedQuery%',
              '%$normalizedQuery%',
              '%$normalizedQuery%',
              '%$normalizedQuery%',
              _normalizePhoneForSearch(normalizedQuery),
              '%${_normalizePhoneForSearch(normalizedQuery)}%',
            ],
          );

    final clients = rows.map(Client.fromMap).toList();
    await _logClientListDiagnostics(
      query: normalizedQuery,
      loadedClients: clients,
    );
    return clients;
  }

  Future<int> countAll() async {
    if (_useBackendMode) {
      return (await _fetchAllFromBackend()).length;
    }

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

    if (_useBackendMode) {
      final clients = await _fetchAllFromBackend(query: normalizedDocumentId);
      for (final client in clients) {
        if (client.documentId.trim() == normalizedDocumentId) {
          return client;
        }
      }
      return null;
    }

    final db = await _appDatabase.database;
    var rows = await db.query(
      DatabaseSchema.clientsTable,
      where: 'cedula = ? AND deleted_at IS NULL',
      whereArgs: [normalizedDocumentId],
      limit: 1,
    );

    if (rows.isEmpty) {
      rows = await db.query(
        DatabaseSchema.clientsTable,
        where: 'LOWER(TRIM(cedula)) = LOWER(TRIM(?)) AND deleted_at IS NULL',
        whereArgs: [normalizedDocumentId],
        limit: 1,
      );
    }

    if (rows.isEmpty) {
      return null;
    }

    return Client.fromMap(rows.first);
  }

  Future<void> save(Client client) async {
    try {
      _systemConfigService.ensureWritable();
      final normalizedClientInput = client.copyWith(
        fullName: client.fullName.trim(),
        documentId: client.documentId.trim(),
        phone: _nullIfBlankPreserve(client.phone),
        address: _nullIfBlank(client.address),
      );

      if (_enforceProductionGuards) {
        if (ClientDataGuard.isTestLikeName(normalizedClientInput.fullName)) {
          throw StateError('No se admiten clientes de prueba en producción.');
        }
        if (!ClientDataGuard.hasValidDocumentId(
          normalizedClientInput.documentId,
        )) {
          throw StateError('La cédula del cliente no es válida.');
        }
      }

      if (_useBackendMode) {
        await _saveToBackend(normalizedClientInput);
        return;
      }

      final db = await _appDatabase.database;
      final now = DateTime.now();
      final normalizedClient = normalizedClientInput.copyWith(
        syncId: _normalizeSyncId(normalizedClientInput.syncId),
        createdAt: normalizedClientInput.id == null
            ? now
            : normalizedClientInput.createdAt,
        updatedAt: now,
        clearDeletedAt: true,
        syncStatus: SyncStatus.pending,
      );

      final duplicateId = await _findActiveClientIdByDocumentId(
        normalizedClient.documentId,
        excludeId: normalizedClient.id,
      );
      if (duplicateId != null) {
        await _logDuplicateClientDiagnostics(
          normalizedClient,
          duplicateId: duplicateId,
        );
        throw StateError(
          'Ya existe un cliente activo con esta cédula. Verifica los datos antes de continuar.',
        );
      }

      final duplicatePhoneId = await _findActiveClientIdByPhone(
        normalizedClient.phone,
        excludeId: normalizedClient.id,
      );
      if (duplicatePhoneId != null) {
        await _logDuplicateClientDiagnostics(
          normalizedClient,
          duplicateId: duplicatePhoneId,
        );
        throw StateError(
          'Ya existe un cliente activo con este teléfono. Verifica los datos antes de continuar.',
        );
      }

      if (normalizedClient.id == null) {
        // Anonimizar cualquier registro eliminado que aún conserve la cédula
        // original (caso: borrado antes de la anonimización o revertido por sync).
        // Esto evita que el UNIQUE constraint de SQLite bloquee el nuevo INSERT.
        await db.rawUpdate(
          "UPDATE ${DatabaseSchema.clientsTable} "
          "SET cedula = '__DELETED__' || CAST(id AS TEXT) "
          'WHERE deleted_at IS NOT NULL '
          'AND LOWER(TRIM(cedula)) = LOWER(TRIM(?))',
          [normalizedClient.documentId],
        );

        final insertedId = await db.insert(
          DatabaseSchema.clientsTable,
          normalizedClient.toMap()
            ..['id_local'] = null
            ..['id_remote'] = null
            ..['last_modified_local'] = now.toIso8601String()
            ..remove('id'),
        );
        _log(
          'CLIENT LOCAL CREATED -> id=$insertedId documentId=${normalizedClient.documentId}',
        );
        _log(
          'Guardado en local -> scope=clients operation=create id=$insertedId sync_status=${SyncStatus.pending.storageValue}',
        );
        _scheduleBackgroundSync('create-client');
        // Garantizar sync inmediato tras crear cliente para todos los usuarios
        _scheduleExplicitSync('create-client:$insertedId');
        return;
      }

      await db.update(
        DatabaseSchema.clientsTable,
        normalizedClient.toMap()
          ..['sync_status'] = DatabaseSchema.syncStatusPendingUpdate
          ..['last_modified_local'] = now.toIso8601String()
          ..remove('id'),
        where: 'id = ?',
        whereArgs: [normalizedClient.id],
      );
      _log(
        'CLIENT LOCAL UPDATED -> id=${normalizedClient.id} documentId=${normalizedClient.documentId}',
      );
      _log(
        'Guardado en local -> scope=clients operation=update id=${normalizedClient.id} sync_status=${SyncStatus.pending.storageValue}',
      );
      _scheduleBackgroundSync('update-client:${normalizedClient.id}');
      // Garantizar sync inmediato tras actualizar cliente para todos los usuarios
      _scheduleExplicitSync('update-client:${normalizedClient.id}');
    } catch (error, stackTrace) {
      print('💥 ERROR SQLITE: $error');
      print(stackTrace);
      _log('CLIENT SAVE ERROR', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> delete(int id) async {
    try {
      _systemConfigService.ensureWritable();
      if (_useBackendMode) {
        await _deleteFromBackend(id);
        return;
      }

      final db = await _appDatabase.database;

      // Blindaje: no borrar cliente con ventas activas
      final activeSaleRows = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM ${DatabaseSchema.salesTable} '
        'WHERE cliente_id = ? AND deleted_at IS NULL '
        "AND LOWER(estado) NOT IN "
        "('cancelada','cancelado','anulada','anulado','eliminada','eliminado')",
        [id],
      );
      final activeSaleCount =
          (activeSaleRows.first['cnt'] as num?)?.toInt() ?? 0;
      if (activeSaleCount > 0) {
        throw const ActiveSalesBlockDeleteException(
          'No puedes eliminar este cliente porque tiene una venta activa '
          'relacionada. Primero debes ir a Ventas y anular o eliminar esa venta.',
        );
      }

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
      final deletedDocument = _deletedDocumentPlaceholder(
        existing.documentId,
        id,
      );
      await db.update(
        DatabaseSchema.clientsTable,
        deletedClient.toMap()
          ..['cedula'] = deletedDocument
          ..['sync_status'] = DatabaseSchema.syncStatusPendingDelete
          ..['last_modified_local'] = now.toIso8601String()
          ..remove('id'),
        where: 'id = ?',
        whereArgs: [id],
      );
      _log('CLIENT LOCAL DELETED -> id=$id');
      _log(
        'Guardado en local -> scope=clients operation=delete id=$id sync_status=${SyncStatus.pending.storageValue}',
      );
      _scheduleBackgroundSync('delete-client:$id');
      // Garantizar sync inmediato tras eliminar cliente para todos los usuarios
      _scheduleExplicitSync('delete-client:$id');
    } catch (error, stackTrace) {
      print('💥 ERROR SQLITE: $error');
      print(stackTrace);
      _log('CLIENT DELETE ERROR', error: error, stackTrace: stackTrace);
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
    _log('Intentando sync -> scope=clients operation=$operationLabel');
    try {
      await _syncQueueService.refreshScope(scope);
      final processed = await _syncQueueService.processQueue(
        includeDeferred: true,
      );
      _log(
        'Sync exitoso -> scope=clients operation=$operationLabel processed=$processed',
      );
    } catch (error, stackTrace) {
      _log(
        'Sync falló -> scope=clients operation=$operationLabel error=$error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.clientsTable,
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
        if (_enforceProductionGuards &&
            ClientDataGuard.shouldBlockClientDownload(record)) {
          final now = DateTime.now();
          final remoteSyncId = _normalizeSyncId(record['sync_id']?.toString());
          var existingRows = await txn.query(
            DatabaseSchema.clientsTable,
            where: 'sync_id = ?',
            whereArgs: [remoteSyncId],
          );

          final rawDocumentId = record['document_id']?.toString() ?? '';
          if (existingRows.isEmpty && rawDocumentId.trim().isNotEmpty) {
            existingRows = await txn.query(
              DatabaseSchema.clientsTable,
              where: 'LOWER(TRIM(cedula)) = LOWER(TRIM(?))',
              whereArgs: [rawDocumentId.trim()],
            );

            if (existingRows.isEmpty) {
              existingRows = await txn.query(
                DatabaseSchema.clientsTable,
                where: 'LOWER(TRIM(cedula)) = LOWER(TRIM(?))',
                whereArgs: [rawDocumentId.trim()],
              );
            }
          }

          if (existingRows.isNotEmpty) {
            final localId = existingRows.first['id'] as int?;
            await txn.update(
              DatabaseSchema.clientsTable,
              {
                'id_remote': record['id']?.toString().trim(),
                'deleted_at': now.toIso8601String(),
                'fecha_actualizacion': now.toIso8601String(),
                'last_modified_remote': now.toIso8601String(),
                'sync_status': SyncStatus.synced.storageValue,
              },
              where: localId != null ? 'id = ?' : 'sync_id = ?',
              whereArgs: localId != null ? [localId] : [remoteSyncId],
            );
          }

          continue;
        }

        final remoteSyncId = _normalizeSyncId(record['sync_id']?.toString());
        final parsedRemoteClient = Client.fromSyncMap(record);
        final remoteClient = parsedRemoteClient.copyWith(
          syncId: remoteSyncId,
          syncStatus: SyncStatus.synced,
          fullName: parsedRemoteClient.fullName.trim(),
          documentId: parsedRemoteClient.documentId.trim(),
          phone: _nullIfBlank(parsedRemoteClient.phone),
          address: _nullIfBlank(parsedRemoteClient.address),
        );
        var existingRows = await txn.query(
          DatabaseSchema.clientsTable,
          where: 'sync_id = ?',
          whereArgs: [remoteClient.syncId],
          limit: 1,
        );

        if (existingRows.isEmpty && remoteClient.documentId.trim().isNotEmpty) {
          existingRows = await txn.query(
            DatabaseSchema.clientsTable,
            where: 'LOWER(TRIM(cedula)) = LOWER(TRIM(?))',
            whereArgs: [remoteClient.documentId.trim()],
            limit: 1,
          );

          if (existingRows.isEmpty) {
            existingRows = await txn.query(
              DatabaseSchema.clientsTable,
              where: 'LOWER(TRIM(cedula)) = LOWER(TRIM(?))',
              whereArgs: [remoteClient.documentId.trim()],
              limit: 1,
            );
          }
        }

        if (existingRows.isEmpty) {
          await txn.insert(DatabaseSchema.clientsTable, {
            ...remoteClient.toMap(),
            'id_remote': record['id']?.toString().trim(),
            'last_modified_remote': remoteClient.updatedAt.toIso8601String(),
          });
          continue;
        }

        final localRow = existingRows.first;
        final localClient = Client.fromMap(localRow);
        final localStatus = (localRow['sync_status']?.toString() ?? '')
            .trim()
            .toLowerCase();
        final localPending = DatabaseSchema.writableSyncStatuses.contains(
          localStatus,
        );
        final localVersion = localClient.version;
        final remoteVersion = remoteClient.version;
        final localModified = DateTime.tryParse(
          localRow['last_modified_local']?.toString() ??
              localRow['fecha_actualizacion']?.toString() ??
              '',
        );
        final remoteModified = DateTime.tryParse(
          record['last_modified_remote']?.toString() ??
              record['updated_at']?.toString() ??
              '',
        );
        final localHasPendingChanges =
            localPending &&
            ((localVersion > remoteVersion) ||
                (localVersion == remoteVersion &&
                    localModified != null &&
                    remoteModified != null &&
                    localModified.isAfter(remoteModified)));
        if (localHasPendingChanges) {
          continue;
        }

        final localId = existingRows.first['id'] as int?;
        final localDeletedAt = localRow['deleted_at']?.toString().trim();
        final remoteDeletedAt = remoteClient.deletedAt
            ?.toIso8601String()
            .trim();
        if (localDeletedAt != null &&
            localDeletedAt.isNotEmpty &&
            (remoteDeletedAt == null || remoteDeletedAt.isEmpty)) {
          continue;
        }
        await txn.update(
          DatabaseSchema.clientsTable,
          remoteClient.toMap()
            ..['id_remote'] = record['id']?.toString().trim()
            ..['last_modified_remote'] = remoteClient.updatedAt
                .toIso8601String()
            ..remove('id'),
          where: localId != null ? 'id = ?' : 'sync_id = ?',
          whereArgs: localId != null ? [localId] : [remoteSyncId],
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

  String? _nullIfBlank(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _nullIfBlankPreserve(String? value) {
    if (value == null) {
      return null;
    }
    return value.trim().isEmpty ? null : value;
  }

  Future<int?> _findActiveClientIdByDocumentId(
    String documentId, {
    int? excludeId,
  }) async {
    final normalized = documentId.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final db = await _appDatabase.database;
    final where = StringBuffer(
      'deleted_at IS NULL AND LOWER(TRIM(cedula)) = LOWER(TRIM(?))',
    );
    final whereArgs = <Object>[normalized];
    if (excludeId != null) {
      where.write(' AND id <> ?');
      whereArgs.add(excludeId);
    }

    final rows = await db.query(
      DatabaseSchema.clientsTable,
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

  Future<int?> _findActiveClientIdByPhone(
    String? phone, {
    int? excludeId,
  }) async {
    final normalized = phone?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    final normalizedForSearch = _normalizePhoneForSearch(normalized);
    final db = await _appDatabase.database;
    final where = StringBuffer(
      'deleted_at IS NULL AND (LOWER(TRIM(telefono)) = LOWER(TRIM(?))',
    );
    final whereArgs = <Object>[normalized];

    if (normalizedForSearch.isNotEmpty) {
      where.write(' OR ${_normalizedPhoneSql('telefono')} = ?');
      whereArgs.add(normalizedForSearch);
    }

    where.write(')');
    if (excludeId != null) {
      where.write(' AND id <> ?');
      whereArgs.add(excludeId);
    }

    final rows = await db.query(
      DatabaseSchema.clientsTable,
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

  Future<void> _logClientListDiagnostics({
    required String query,
    required List<Client> loadedClients,
  }) async {
    try {
      final tracked = loadedClients.where(_isTrackedYosairaClient).toList();
      final id127 = loadedClients.any((client) => client.id == 127);
      _log(
        '[CLIENT-DIAG][LIST] query="$query" loaded=${loadedClients.length} id127Visible=$id127 tracked=${tracked.map((client) => 'id=${client.id} name=${client.fullName} document=${client.documentId} phone=${client.phone} status=${client.syncStatus.storageValue}').join(' | ')}',
      );
    } catch (_) {
      // Diagnostic logging must never affect client loading.
    }
  }

  Future<void> _logDuplicateClientDiagnostics(
    Client attemptedClient, {
    required int duplicateId,
  }) async {
    try {
      final db = await _appDatabase.database;
      final rows = await db.query(
        DatabaseSchema.clientsTable,
        columns: [
          'id',
          'nombre',
          'cedula',
          'telefono',
          'deleted_at',
          'sync_status',
        ],
        where: 'id = ?',
        whereArgs: [duplicateId],
        limit: 1,
      );
      _log(
        '[CLIENT-DIAG][DUPLICATE] attempted name=${attemptedClient.fullName} document=${attemptedClient.documentId} phone=${attemptedClient.phone} normalizedPhone=${_normalizePhoneForSearch(attemptedClient.phone ?? '')} blocker=${rows.isEmpty ? 'not-found' : rows.first}',
      );
    } catch (_) {
      // Diagnostic logging must never affect duplicate validation.
    }
  }

  bool _isTrackedYosairaClient(Client client) {
    final name = client.fullName.toUpperCase();
    return name.contains('YOSAIRA') ||
        name.contains('YOSAYRA') ||
        client.id == 127;
  }

  String _normalizePhoneForSearch(String value) {
    return value.replaceAll(RegExp(r'[\s\-\(\)\.\+]'), '');
  }

  String _normalizedPhoneSql(String columnName) {
    return "REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(COALESCE($columnName, ''), ' ', ''), '-', ''), '(', ''), ')', ''), '.', ''), '+', '')";
  }

  String _deletedDocumentPlaceholder(String documentId, int id) {
    final normalized = documentId.trim();
    if (normalized.startsWith('__DELETED__')) {
      return normalized;
    }
    return '__DELETED__$id';
  }

  Future<List<Client>> _fetchAllFromBackend({String query = ''}) async {
    final response = await _apiClient.get(
      '/business/clients',
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
    final data = payload['data'];
    final dataMap = data is Map
        ? data.map((key, value) => MapEntry(key.toString(), value))
        : payload;
    final items = (dataMap['items'] as List?) ?? const [];
    final rawItems = items
        .whereType<Map>()
        .map(
          (item) => item.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList(growable: false);
    // Snapshot cache-first de la lista completa (no de busquedas).
    if (query.trim().isEmpty) {
      await _listSnapshot.write(rawItems);
    }
    return rawItems.map(_clientFromBackend).toList(growable: false);
  }

  /// Ultima lista valida de clientes en cache local (best-effort).
  Future<List<Client>> fetchCachedList() async {
    if (!_useBackendMode) {
      return const [];
    }
    final items = await _listSnapshot.read();
    if (items == null) {
      return const [];
    }
    try {
      return items
          .whereType<Map>()
          .map(
            (item) => _clientFromBackend(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveToBackend(Client client) async {
    final payload = _toBackendPayload(client);
    final remoteId =
        _idRegistry.resolveRemoteId('clients', client.id) ??
        client.syncId?.trim();
    if (remoteId == null || remoteId.isEmpty) {
      final response = await _apiClient.post('/business/clients', body: payload);
      await _cacheBackendClientResponse(response);
      await _listSnapshot.clear();
      return;
    }

    final response = await _apiClient.patch(
      '/business/clients/$remoteId',
      body: payload,
    );
    await _cacheBackendClientResponse(response);
    await _listSnapshot.clear();
  }

  Future<void> _deleteFromBackend(int localId) async {
    final remoteId = _idRegistry.resolveRemoteId('clients', localId);
    if (remoteId == null || remoteId.isEmpty) {
      throw const BackendApiException(
        'No se pudo identificar el cliente remoto para eliminarlo.',
      );
    }
    final response = await _apiClient.delete('/business/clients/$remoteId');
    await _cacheBackendClientResponse(response);
    await _listSnapshot.clear();
  }

  Client _clientFromBackend(Map<String, dynamic> item) {
    final remoteId = item['id']?.toString().trim() ?? '';
    final localId = _idRegistry.register('clients', remoteId);
    final firstName = item['firstName']?.toString().trim() ?? '';
    final lastName = item['lastName']?.toString().trim() ?? '';
    final backendName =
        item['name']?.toString().trim() ??
        item['full_name']?.toString().trim() ??
        '';
    final fullName = backendName.isNotEmpty
        ? backendName
        : [
            firstName,
            lastName,
          ].where((value) => value.isNotEmpty).join(' ').trim();
    return Client(
      id: localId,
      syncId: item['syncId']?.toString().trim().isNotEmpty == true
          ? item['syncId']?.toString().trim()
          : remoteId,
      version: _readIntFromDynamic(item['version']) ?? 1,
      fullName: fullName,
      documentId:
          item['document']?.toString().trim() ??
          item['documentId']?.toString().trim() ??
          item['document_id']?.toString().trim() ??
          '',
      phone: _nullIfBlank(item['phone']?.toString()),
      address: _nullIfBlank(item['address']?.toString()),
      createdAt:
          DateTime.tryParse(item['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(item['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      deletedAt: null,
      syncStatus: SyncStatus.synced,
    );
  }

  Map<String, dynamic> _toBackendPayload(Client client) {
    return {
      if (client.syncId?.trim().isNotEmpty == true)
        'syncId': client.syncId!.trim(),
      'name': client.fullName.trim(),
      'document': client.documentId.trim(),
      'phone': _nullIfBlank(client.phone),
      'address': _nullIfBlank(client.address),
    };
  }

  Future<void> _cacheBackendClientResponse(Object? response) async {
    final item = _entityFromResponse(response, 'client');
    if (item == null) return;
    await mergeRemoteRecords([_backendClientSyncRecord(item)]);
  }

  Map<String, dynamic>? _entityFromResponse(Object? response, String key) {
    if (response is! Map) return null;
    final payload = response.map((mapKey, value) => MapEntry(mapKey.toString(), value));
    final data = payload['data'];
    final dataMap = data is Map
        ? data.map((mapKey, value) => MapEntry(mapKey.toString(), value))
        : payload;
    final entity = dataMap[key];
    if (entity is Map) {
      return entity.map((mapKey, value) => MapEntry(mapKey.toString(), value));
    }
    return null;
  }

  Map<String, dynamic> _backendClientSyncRecord(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'sync_id': item['sync_id'] ?? item['syncId'] ?? item['id'],
      'version': item['version'] ?? 1,
      'full_name': item['full_name'] ?? item['name'],
      'document_id':
          item['document_id'] ?? item['documentId'] ?? item['document'],
      'phone': item['phone'],
      'address': item['address'],
      'created_at': item['created_at'] ?? item['createdAt'],
      'updated_at': item['updated_at'] ?? item['updatedAt'],
      'deleted_at': item['deleted_at'] ?? item['deletedAt'],
      'sync_status': SyncStatus.synced.storageValue,
    };
  }

  int? _readIntFromDynamic(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
