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
  LotRepository({AppDatabase? appDatabase, SyncQueueService? syncQueueService})
    : _appDatabase = appDatabase ?? AppDatabase.instance,
      _syncQueueService = syncQueueService ?? SyncQueueService.instance;

  final AppDatabase _appDatabase;
  final SyncQueueService _syncQueueService;

  Future<List<Lot>> fetchAll({String query = ''}) async {
    return _fetchWhere(
      query: query,
      wherePrefix: null,
      wherePrefixArgs: const [],
    );
  }

  Future<List<Lot>> fetchAvailable({String query = ''}) async {
    return _fetchWhere(
      query: query,
      wherePrefix: 'estado = ?',
      wherePrefixArgs: const ['disponible'],
    );
  }

  Future<Lot?> findById(int id) async {
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
    SystemConfigService.instance.ensureWritable();

    final db = await _appDatabase.database;
    await db.update(
      DatabaseSchema.lotsTable,
      {
        'estado': status,
        'fecha_actualizacion': DateTime.now().toIso8601String(),
        'sync_status': DatabaseSchema.syncStatusPending,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _confirmAuthoritativeSync('update-lot-status:$id');
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
    SystemConfigService.instance.ensureWritable();

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
      await db.insert(
        DatabaseSchema.lotsTable,
        normalizedLot.copyWith(createdAt: now, updatedAt: now).toMap()
          ..['sync_id'] = _newSyncId()
          ..['deleted_at'] = null
          ..['sync_status'] = DatabaseSchema.syncStatusPending
          ..remove('id'),
      );
      await _confirmAuthoritativeSync('create-lot');
      return;
    }

    await db.update(
      DatabaseSchema.lotsTable,
      normalizedLot.copyWith(updatedAt: now).toMap()
        ..['sync_status'] = DatabaseSchema.syncStatusPending
        ..remove('id'),
      where: 'id = ?',
      whereArgs: [normalizedLot.id],
    );
    await _confirmAuthoritativeSync('update-lot:${normalizedLot.id}');
  }

  Future<void> delete(int id) async {
    SystemConfigService.instance.ensureWritable();

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
      'sync_status': DatabaseSchema.syncStatusPending,
    };
    final syncId = (row['sync_id'] as String?)?.trim();

    await db.update(
      DatabaseSchema.lotsTable,
      {
        'deleted_at': payload['deleted_at'],
        'fecha_actualizacion': payload['updated_at'],
        'sync_status': DatabaseSchema.syncStatusPending,
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
    await _confirmAuthoritativeSync('delete-lot:$id');
  }

  Future<void> _confirmAuthoritativeSync(String operationLabel) async {
    await _syncQueueService.refreshScope('products');
    await _syncQueueService.syncScopesNowOrThrow(
      const ['products'],
      operationLabel: operationLabel,
    );
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
}
