import 'dart:async';
import 'dart:developer' as developer;

import '../../../core/network/backend_api_client.dart';
import '../../../core/network/backend_entity_id_registry.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../../../core/system/system_config_service.dart';
import '../../../services/sync/sync_queue_service.dart';
import '../domain/lot.dart';

class DuplicateLotException implements Exception {
  DuplicateLotException(this.existingLot);

  final Lot existingLot;

  String get message {
    final status = switch (existingLot.status.trim().toLowerCase()) {
      'reservado' => 'reservado',
      'vendido' => 'vendido',
      _ => 'disponible',
    };

    return 'Ya existe el solar ${existingLot.displayCode} y actualmente está $status.';
  }

  @override
  String toString() => message;
}

class LotRepository {
  LotRepository({
    AppDatabase? appDatabase,
    SyncQueueService? syncQueueService,
    BackendApiClient? apiClient,
  }) : _appDatabase = appDatabase ?? AppDatabase.instance,
       _syncQueueService = syncQueueService ?? SyncQueueService.instance,
       _apiClient = apiClient ?? BackendApiClient();

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
      name: 'SistemaSolares.LotRepository',
      error: error,
      stackTrace: stackTrace,
    );
  }

  Future<List<Lot>> fetchAll({String query = ''}) async {
    if (_useBackendMode) {
      return _fetchAllFromBackend(query: query, onlyAvailable: false);
    }

    return _fetchWhere(
      query: query,
      wherePrefix: null,
      wherePrefixArgs: const [],
    );
  }

  Future<List<Lot>> fetchAvailable({String query = ''}) async {
    if (_useBackendMode) {
      return _fetchAllFromBackend(query: query, onlyAvailable: true);
    }

    return _fetchWhere(
      query: query,
      wherePrefix: 'estado = ?',
      wherePrefixArgs: const ['disponible'],
    );
  }

  Future<Lot?> findById(int id) async {
    if (_useBackendMode) {
      final lots = await _fetchAllFromBackend(onlyAvailable: false);
      for (final lot in lots) {
        if (lot.id == id) {
          return lot;
        }
      }
      return null;
    }

    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.lotsTable,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );

    if (rows.isEmpty) {
      return null;
    }

    return Lot.fromMap(rows.first);
  }

  Future<Lot?> findByBlockAndLotNumber({
    required String blockNumber,
    required String lotNumber,
  }) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.lotsTable,
      where: 'manzana_numero = ? AND solar_numero = ? AND deleted_at IS NULL',
      whereArgs: [blockNumber.trim(), lotNumber.trim()],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return Lot.fromMap(rows.first);
  }

  Future<void> updateStatus(int id, String status) async {
    try {
      if (_useBackendMode) {
        final remoteId = _idRegistry.resolveRemoteId('products', id);
        if (remoteId == null || remoteId.isEmpty) {
          throw const BackendApiException(
            'No se pudo identificar el solar remoto para actualizarlo.',
          );
        }
        await _apiClient.patch(
          '/products/$remoteId',
          body: {
            'stock': status == 'disponible' ? 1 : 0,
            'isActive': status != 'vendido',
          },
        );
        return;
      }

      final db = await _appDatabase.database;
      await db.update(
        DatabaseSchema.lotsTable,
        {
          'estado': status,
          'fecha_actualizacion': DateTime.now().toIso8601String(),
          'sync_status': DatabaseSchema.syncStatusPendingUpdate,
          'last_modified_local': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      _log('LOT LOCAL STATUS UPDATED -> id=$id status=$status');
      _scheduleBackgroundSync('update-lot-status:$id');
    } catch (error, stackTrace) {
      print('💥 ERROR SQLITE: $error');
      print(stackTrace);
      _log('LOT STATUS ERROR', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<List<Lot>> _fetchWhere({
    required String query,
    required String? wherePrefix,
    required List<Object?> wherePrefixArgs,
  }) async {
    final db = await _appDatabase.database;
    final normalizedQuery = query.trim();
    final queryClause = normalizedQuery.isEmpty
        ? null
        : '(manzana_numero LIKE ? OR solar_numero LIKE ? OR estado LIKE ?)';
    final queryArgs = queryClause == null
        ? <Object?>[]
        : List<Object?>.filled(3, '%$normalizedQuery%');

    final where = [
      'deleted_at IS NULL',
      ...?wherePrefix == null ? null : [wherePrefix],
      ...?queryClause == null ? null : [queryClause],
    ].join(' AND ');

    final rows = await db.query(
      DatabaseSchema.lotsTable,
      where: where.isEmpty ? null : where,
      whereArgs: [...wherePrefixArgs, ...queryArgs],
      orderBy:
          'manzana_numero COLLATE NOCASE ASC, solar_numero COLLATE NOCASE ASC',
    );

    return rows.map(Lot.fromMap).toList();
  }

  Future<int> countAll() async {
    final db = await _appDatabase.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) FROM ${DatabaseSchema.lotsTable} WHERE deleted_at IS NULL',
    );
    return _readCount(result);
  }

  Future<int> countByStatus(String status) async {
    final db = await _appDatabase.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) FROM ${DatabaseSchema.lotsTable} WHERE deleted_at IS NULL AND estado = ?',
      [status],
    );
    return _readCount(result);
  }

  Future<void> save(Lot lot) async {
    try {
      SystemConfigService.instance.ensureWritable();
      if (_useBackendMode) {
        await _saveToBackend(lot);
        return;
      }

      final db = await _appDatabase.database;
      final now = DateTime.now();
      final normalizedBlock = lot.blockNumber.trim();
      final normalizedLotNumber = lot.lotNumber.trim();
      final existingLot = await findByBlockAndLotNumber(
        blockNumber: normalizedBlock,
        lotNumber: normalizedLotNumber,
      );

      if (existingLot != null && existingLot.id != lot.id) {
        throw DuplicateLotException(existingLot);
      }

      final normalizedLot = lot.copyWith(
        blockNumber: normalizedBlock,
        lotNumber: normalizedLotNumber,
      );

      if (normalizedLot.id == null) {
        final insertedId = await db.insert(
          DatabaseSchema.lotsTable,
          normalizedLot.copyWith(createdAt: now, updatedAt: now).toMap()
            ..['sync_id'] = _newSyncId()
            ..['id_local'] = null
            ..['id_remote'] = null
            ..['last_modified_local'] = now.toIso8601String()
            ..['deleted_at'] = null
            ..['sync_status'] = DatabaseSchema.syncStatusPendingCreate
            ..remove('id'),
        );
        _log(
          'LOT LOCAL CREATED -> id=$insertedId code=${normalizedLot.displayCode}',
        );
        _scheduleBackgroundSync('create-lot');
        return;
      }

      await db.update(
        DatabaseSchema.lotsTable,
        normalizedLot.copyWith(updatedAt: now).toMap()
          ..['sync_status'] = DatabaseSchema.syncStatusPendingUpdate
          ..['last_modified_local'] = now.toIso8601String()
          ..remove('id'),
        where: 'id = ?',
        whereArgs: [normalizedLot.id],
      );
      _log(
        'LOT LOCAL UPDATED -> id=${normalizedLot.id} code=${normalizedLot.displayCode}',
      );
      _scheduleBackgroundSync('update-lot:${normalizedLot.id}');
    } catch (error, stackTrace) {
      print('💥 ERROR SQLITE: $error');
      print(stackTrace);
      _log('LOT SAVE ERROR', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> delete(int id) async {
    try {
      SystemConfigService.instance.ensureWritable();
      if (_useBackendMode) {
        final remoteId = _idRegistry.resolveRemoteId('products', id);
        if (remoteId == null || remoteId.isEmpty) {
          throw const BackendApiException(
            'No se pudo identificar el solar remoto para eliminarlo.',
          );
        }
        await _apiClient.delete('/products/$remoteId');
        return;
      }

      final db = await _appDatabase.database;
      final rows = await db.query(
        DatabaseSchema.lotsTable,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        return;
      }

      final row = rows.first;
      final payload = {
        'id': row['id'],
        'sync_id': row['sync_id'],
        'version': ((row['version'] as int?) ?? 1) + 1,
        'block_number': row['manzana_numero'],
        'lot_number': row['solar_numero'],
        'area': row['metros_cuadrados'],
        'price_per_square_meter': row['precio_por_metro'],
        'status': row['estado'],
        'created_at': row['fecha_creacion'],
        'updated_at': DateTime.now().toIso8601String(),
        'deleted_at': DateTime.now().toIso8601String(),
        'sync_status': DatabaseSchema.syncStatusPendingDelete,
      };
      final syncId = (row['sync_id'] as String?)?.trim();

      await db.update(
        DatabaseSchema.lotsTable,
        {
          'deleted_at': payload['deleted_at'],
          'fecha_actualizacion': payload['updated_at'],
          'sync_status': DatabaseSchema.syncStatusPendingDelete,
          'last_modified_local': payload['updated_at'],
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (syncId != null && syncId.isNotEmpty) {
        await _syncQueueService.enqueueDelete(
          scope: 'products',
          recordSyncId: syncId,
          payload: payload,
        );
      }
      _log('LOT LOCAL DELETED -> id=$id');
      _scheduleBackgroundSync('delete-lot:$id');
    } catch (error, stackTrace) {
      print('💥 ERROR SQLITE: $error');
      print(stackTrace);
      _log('LOT DELETE ERROR', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  void _scheduleBackgroundSync(String operationLabel) {
    if (!_shouldRunBackgroundSync) {
      return;
    }
    unawaited(_runBackgroundSync(operationLabel));
  }

  Future<void> _runBackgroundSync(String operationLabel) async {
    _log('LOT SYNC ATTEMPT -> operation=$operationLabel');
    try {
      await _syncQueueService.refreshScope('products');
      final processed = await _syncQueueService.processQueue(
        includeDeferred: true,
      );
      _log('LOT SYNC RESULT -> operation=$operationLabel processed=$processed');
    } catch (error, stackTrace) {
      _log(
        'LOT SYNC ERROR -> operation=$operationLabel',
        error: error,
        stackTrace: stackTrace,
      );
    }
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

  String _newSyncId() {
    return 'product-${DateTime.now().microsecondsSinceEpoch}';
  }

  Future<List<Lot>> _fetchAllFromBackend({
    String query = '',
    required bool onlyAvailable,
  }) async {
    final response = await _apiClient.get(
      '/products',
      queryParameters: {
        'page': '1',
        'limit': '100',
        'includeInactive': 'true',
        'includeDeleted': 'false',
        if (query.trim().isNotEmpty) 'search': query.trim(),
      },
    );
    final payload = response is Map<String, dynamic>
        ? response
        : (response as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          );
    final items = (payload['items'] as List?) ?? const [];
    final lots = items
        .whereType<Map>()
        .map(
          (item) => _lotFromBackend(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
    if (!onlyAvailable) {
      return lots;
    }
    return lots
        .where((lot) => lot.status == 'disponible')
        .toList(growable: false);
  }

  Future<void> _saveToBackend(Lot lot) async {
    final payload = {
      'code': lot.displayCode,
      'name': 'Solar ${lot.displayCode}',
      'description': 'Solar ${lot.displayCode} · ${lot.area} m2',
      'price': lot.totalPrice,
      'financingPrice': lot.totalPrice,
      'stock': lot.status == 'disponible' ? 1 : 0,
      'isActive': lot.status != 'vendido',
    };
    final remoteId = _idRegistry.resolveRemoteId('products', lot.id);
    if (remoteId == null || remoteId.isEmpty) {
      await _apiClient.post('/products', body: payload);
      return;
    }

    await _apiClient.patch('/products/$remoteId', body: payload);
  }

  Lot _lotFromBackend(Map<String, dynamic> item) {
    final remoteId = item['id']?.toString().trim() ?? '';
    final localId = _idRegistry.register('products', remoteId);
    final syncPayload = item['syncPayload'];
    final payload = syncPayload is Map<String, dynamic>
        ? syncPayload
        : syncPayload is Map
        ? syncPayload.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final code = item['code']?.toString() ?? item['name']?.toString() ?? '';
    final blockNumber =
        payload['block_number']?.toString() ?? _extractBlockNumber(code);
    final lotNumber =
        payload['lot_number']?.toString() ?? _extractLotNumber(code);
    final area = _toDouble(payload['area']) > 0
        ? _toDouble(payload['area'])
        : 1.0;
    final unitPrice = _toDouble(payload['price_per_square_meter']) > 0
        ? _toDouble(payload['price_per_square_meter'])
        : (area > 0 ? _toDouble(item['price']) / area : 0.0);
    final rawStatus = payload['status']?.toString().trim().toLowerCase();
    final status = rawStatus == null || rawStatus.isEmpty
        ? ((_toInt(item['stock']) > 0 && item['isActive'] == true)
              ? 'disponible'
              : 'vendido')
        : rawStatus;

    return Lot(
      id: localId,
      blockNumber: blockNumber,
      lotNumber: lotNumber,
      area: area,
      pricePerSquareMeter: unitPrice,
      status: status,
      createdAt:
          DateTime.tryParse(item['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(item['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _extractBlockNumber(String raw) {
    final match = RegExp(r'M([A-Z0-9]+)', caseSensitive: false).firstMatch(raw);
    return match?.group(1) ?? '';
  }

  String _extractLotNumber(String raw) {
    final match = RegExp(r'S([A-Z0-9]+)', caseSensitive: false).firstMatch(raw);
    return match?.group(1) ?? '';
  }
}
