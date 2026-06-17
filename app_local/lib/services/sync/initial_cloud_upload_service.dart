import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_schema.dart';
import '../../core/network/backend_http_client.dart';
import '../../models/sync/sync_settings.dart';
import 'sync_api_client.dart';
import 'sync_config_repository.dart';

/// Servicio responsable de la sincronización inicial completa local -> nube.
///
/// Cuando un cliente actualiza la app y ya tiene datos históricos en SQLite
/// que nunca fueron subidos a la nube (porque existían antes de que existiera
/// sync_queue), este servicio se encarga de subir TODO el contenido local
/// al backend una sola vez.
///
/// Reglas:
/// - SQLite local sigue siendo la fuente de verdad.
/// - No activa cloud pull.
/// - No descarga nube -> local.
/// - No borra datos.
/// - No hace hard delete.
/// - No rompe sync_queue.
/// - No duplica registros en backend (usa sync_id como identidad).
/// - La app debe abrir normal aunque el backend no esté disponible.
class InitialCloudUploadService {
  InitialCloudUploadService({
    AppDatabase? appDatabase,
    SyncConfigRepository? configRepository,
    SyncApiClient? apiClient,
  }) : _appDatabase = appDatabase ?? AppDatabase.instance,
       _configRepository = configRepository ?? SyncConfigRepository(),
       _apiClient = apiClient ?? SyncApiClient();

  final AppDatabase _appDatabase;
  final SyncConfigRepository _configRepository;
  final SyncApiClient _apiClient;

  static const int _batchSize = 200;
  static const String _logPrefix = '[InitialCloudUpload]';

  /// Orden de subida respetando dependencias.
  static const List<String> _uploadOrder = [
    'clients',
    'sellers',
    'products',
    'sales',
    'installments',
    'payments',
  ];

  void _log(String message) {
    final line = '$_logPrefix $message';
    debugPrint(line);
    developer.log(line, name: 'SistemaSolares.InitialCloudUpload');
  }

  /// Punto de entrada principal.
  ///
  /// Debe llamarse después de que el backend esté configurado (JWT presente)
  /// y la conexión esté verificada.
  ///
  /// Retorna true si la sincronización inicial se completó exitosamente,
  /// false si falló o ya estaba completada.
  Future<bool> run({required SyncSettings settings}) async {
    final backendUrl = settings.normalizedBaseUrl;

    // 1. Verificar si ya se completó (comparando backend URL)
    final alreadyCompleted = await _configRepository
        .isLocalUploadBootstrapCompleted(backendUrl: backendUrl);
    if (alreadyCompleted) {
      _log('already completed, skipping');
      return true;
    }

    _log('starting');

    // 2. Verificar backend online
    if (!await _isBackendOnline(settings)) {
      _log('backend offline, pending retry');
      return false;
    }
    _log('backend online');

    // 3. Leer todos los datos locales
    final allData = await _readAllLocalData();

    // 4. Log counts
    for (final scope in _uploadOrder) {
      final count = allData[scope]?.length ?? 0;
      _log('$scope count=$count');
    }

    // 5. Subir por lotes respetando orden
    int totalRejected = 0;
    try {
      for (final scope in _uploadOrder) {
        final records = allData[scope] ?? [];
        if (records.isEmpty) {
          continue;
        }

        final result = await _uploadScopeInBatches(
          settings: settings,
          scope: scope,
          records: records,
        );
        if (!result.success) {
          _log('upload failed scope=$scope -> pending retry');
          return false;
        }
        totalRejected += result.rejectedCount;
      }
    } on SocketException {
      _log('network error -> pending retry');
      return false;
    } on HttpException catch (error) {
      _log('http error -> pending retry: $error');
      return false;
    } catch (error) {
      _log('unexpected error -> pending retry: $error');
      return false;
    }

    // 6. Si hay registros rechazados, no marcar completado
    if (totalRejected > 0) {
      _log('total rejected=$totalRejected -> pending retry, will not mark completed');
      return false;
    }

    // 7. Marcar como completado con metadatos
    await _configRepository.markLocalUploadBootstrapCompleted(
      backendUrl: backendUrl,
    );
    _log('completed');
    return true;
  }

  /// Verifica que el backend esté online usando /system/status
  /// y /system/config como fallback.
  /// NOTA: settings.normalizedBaseUrl ya incluye /api, por lo que
  /// las rutas completas son $baseUrl/system/status y $baseUrl/system/config.
  Future<bool> _isBackendOnline(SyncSettings settings) async {
    final baseUrl = settings.normalizedBaseUrl;
    final httpClient = createBackendHttpClient(
      connectionTimeout: const Duration(seconds: 8),
      idleTimeout: const Duration(seconds: 10),
    );

    try {
      // Intentar /system/status primero (baseUrl ya incluye /api)
      final statusUri = Uri.parse('$baseUrl/system/status');
      try {
        final request = await httpClient.getUrl(statusUri);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        if (response.statusCode == 200) {
          return true;
        }
      } catch (_) {
        // Fallback a /system/config
      }

      // Fallback
      final configUri = Uri.parse('$baseUrl/system/config');
      try {
        final request = await httpClient.getUrl(configUri);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        return response.statusCode == 200;
      } catch (_) {
        return false;
      }
    } finally {
      httpClient.close(force: true);
    }
  }

  /// Lee TODOS los registros de todas las tablas locales, incluyendo:
  /// - activos y eliminados (soft delete)
  /// - cualquier sync_status (synced, pending_create, pending_update, etc.)
  /// - datos sin sync_id (genera sync_id estable)
  Future<Map<String, List<Map<String, Object?>>>> _readAllLocalData() async {
    final db = await _appDatabase.database;
    final result = <String, List<Map<String, Object?>>>{
      'clients': [],
      'sellers': [],
      'products': [],
      'sales': [],
      'installments': [],
      'payments': [],
    };

    // Clientes
    final clients = await db.query(DatabaseSchema.clientsTable);
    for (final row in clients) {
      await _ensureSyncId(db, DatabaseSchema.clientsTable, row);
      result['clients']!.add(_clientToPayload(row));
    }

    // Vendedores
    final sellers = await db.query(DatabaseSchema.sellersTable);
    for (final row in sellers) {
      await _ensureSyncId(db, DatabaseSchema.sellersTable, row);
      result['sellers']!.add(_sellerToPayload(row));
    }

    // Solares/Lotes
    final lots = await db.query(DatabaseSchema.lotsTable);
    for (final row in lots) {
      await _ensureSyncId(db, DatabaseSchema.lotsTable, row);
      result['products']!.add(_lotToPayload(row));
    }

    // Ventas (con sync_ids de relaciones)
    final sales = await db.rawQuery('''
      SELECT
        v.*,
        c.sync_id AS client_sync_id,
        s.sync_id AS product_sync_id,
        vd.sync_id AS seller_sync_id
      FROM ${DatabaseSchema.salesTable} v
      LEFT JOIN ${DatabaseSchema.clientsTable} c ON c.id = v.cliente_id
      LEFT JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      LEFT JOIN ${DatabaseSchema.sellersTable} vd ON vd.id = v.vendedor_id
    ''');
    for (final row in sales) {
      await _ensureSyncId(db, DatabaseSchema.salesTable, row);
      result['sales']!.add(_saleToPayload(row));
    }

    // Cuotas (con sale_sync_id)
    final installments = await db.rawQuery('''
      SELECT
        q.*,
        v.sync_id AS sale_sync_id
      FROM ${DatabaseSchema.installmentsTable} q
      INNER JOIN ${DatabaseSchema.salesTable} v ON v.id = q.venta_id
    ''');
    for (final row in installments) {
      await _ensureSyncId(db, DatabaseSchema.installmentsTable, row);
      result['installments']!.add(_installmentToPayload(row));
    }

    // Pagos (con sale_sync_id, client_sync_id, installment_sync_id)
    final payments = await db.rawQuery('''
      SELECT
        p.*,
        v.sync_id AS sale_sync_id,
        c.sync_id AS client_sync_id,
        q.sync_id AS installment_sync_id
      FROM ${DatabaseSchema.paymentsTable} p
      INNER JOIN ${DatabaseSchema.salesTable} v ON v.id = p.venta_id
      INNER JOIN ${DatabaseSchema.clientsTable} c ON c.id = p.cliente_id
      LEFT JOIN ${DatabaseSchema.installmentsTable} q ON q.id = p.cuota_id
    ''');
    for (final row in payments) {
      await _ensureSyncId(db, DatabaseSchema.paymentsTable, row);
      result['payments']!.add(_paymentToPayload(row));
    }

    return result;
  }

  /// Asegura que el registro tenga un sync_id estable.
  /// Si no tiene sync_id, genera uno determinista basado en el id local
  /// y lo persiste en SQLite para que no cambie entre reinicios.
  Future<void> _ensureSyncId(
    dynamic db,
    String tableName,
    Map<String, Object?> row,
  ) async {
    final currentSyncId = row['sync_id']?.toString().trim() ?? '';
    if (currentSyncId.isNotEmpty) {
      return;
    }

    final rowId = row['id'];
    if (rowId == null) {
      return;
    }

    // Generar sync_id determinista: "init_{table}_{id}"
    // Esto asegura que el mismo registro siempre tenga el mismo sync_id
    // incluso si se reintenta la sincronización inicial.
    final newSyncId = 'init_${tableName}_$rowId';
    row['sync_id'] = newSyncId;

    await db.update(
      tableName,
      {'sync_id': newSyncId},
      where: 'id = ?',
      whereArgs: [rowId],
    );
    _log('generated sync_id for $tableName id=$rowId sync_id=$newSyncId');
  }

  /// Sube los registros de un scope en lotes.
  /// Retorna (success, rejectedCount).
  Future<({bool success, int rejectedCount})> _uploadScopeInBatches({
    required SyncSettings settings,
    required String scope,
    required List<Map<String, Object?>> records,
  }) async {
    int totalRejected = 0;
    for (var i = 0; i < records.length; i += _batchSize) {
      final end = (i + _batchSize > records.length)
          ? records.length
          : i + _batchSize;
      final batch = records.sublist(i, end);

      _log('uploading scope=$scope count=${batch.length} batch=${i ~/ _batchSize + 1}/${(records.length / _batchSize).ceil()}');

      final recordsByScope = <String, List<Map<String, Object?>>>{
        scope: batch,
      };

      try {
        final response = await _apiClient.uploadQueuedRecords(
          settings: settings,
          recordsByScope: recordsByScope,
        );

        final returnedRecords = response.returnedRecordsByScope[scope] ?? [];
        final applied = returnedRecords.length;
        final rejected = batch.length - applied;
        totalRejected += rejected;

        _log('upload success scope=$scope applied=$applied rejected=$rejected');
      } on HttpException catch (error) {
        _log('upload failed scope=$scope batch=${i ~/ _batchSize + 1}: $error');
        return (success: false, rejectedCount: totalRejected);
      } on SocketException {
        _log('upload network error scope=$scope batch=${i ~/ _batchSize + 1}');
        return (success: false, rejectedCount: totalRejected);
      }
    }

    return (success: true, rejectedCount: totalRejected);
  }

  // ---- Payload builders ----

  Map<String, Object?> _clientToPayload(Map<String, Object?> row) {
    return {
      'sync_id': row['sync_id'],
      'version': row['version'] ?? 1,
      'nombre': row['nombre'],
      'cedula': row['cedula'],
      'telefono': row['telefono'],
      'direccion': row['direccion'],
      'created_at': row['fecha_creacion'],
      'updated_at': row['fecha_actualizacion'],
      'deleted_at': row['deleted_at'],
    };
  }

  Map<String, Object?> _sellerToPayload(Map<String, Object?> row) {
    return {
      'sync_id': row['sync_id'],
      'version': row['version'] ?? 1,
      'nombre': row['nombre'],
      'cedula': row['cedula'],
      'telefono': row['telefono'],
      'activo': row['activo'] ?? true,
      'created_at': row['fecha_creacion'],
      'updated_at': row['fecha_actualizacion'],
      'deleted_at': row['deleted_at'],
    };
  }

  Map<String, Object?> _lotToPayload(Map<String, Object?> row) {
    return {
      'sync_id': row['sync_id'],
      'version': row['version'] ?? 1,
      'block_number': row['manzana_numero'],
      'lot_number': row['solar_numero'],
      'area': row['metros_cuadrados'],
      'price_per_square_meter': row['precio_por_metro'],
      'status': row['estado'],
      'created_at': row['fecha_creacion'],
      'updated_at': row['fecha_actualizacion'],
      'deleted_at': row['deleted_at'],
    };
  }

  Map<String, Object?> _saleToPayload(Map<String, Object?> row) {
    return {
      'sync_id': row['sync_id'],
      'version': row['version'] ?? 1,
      'client_sync_id': row['client_sync_id'],
      'product_sync_id': row['product_sync_id'],
      'seller_sync_id': row['seller_sync_id'],
      'sale_date': row['fecha_venta'],
      'sale_price': row['precio_venta'],
      'down_payment_percentage': row['inicial_porcentaje'],
      'down_payment_amount': row['inicial_monto'],
      'required_initial_payment': row['monto_inicial_requerido'],
      'paid_initial_payment': row['monto_inicial_pagado'],
      'pending_initial_payment': row['monto_inicial_pendiente'],
      'minimum_reserve_amount': row['monto_apartado_minimo'],
      'initial_payment_deadline': row['fecha_limite_inicial'],
      'activation_date': row['fecha_activacion'],
      'financed_balance': row['saldo_financiado'],
      'pending_balance': row['saldo_pendiente'],
      'monthly_interest': row['interes_mensual'],
      'installment_count': row['cantidad_cuotas'],
      'status': row['estado'],
      'created_at': row['fecha_creacion'],
      'updated_at': row['fecha_actualizacion'],
      'deleted_at': row['deleted_at'],
    };
  }

  Map<String, Object?> _installmentToPayload(Map<String, Object?> row) {
    return {
      'sync_id': row['sync_id'],
      'version': row['version'] ?? 1,
      'sale_sync_id': row['sale_sync_id'],
      'installment_number': row['numero_cuota'],
      'due_date': row['fecha_vencimiento'],
      'opening_balance': row['saldo_inicial'],
      'principal_amount': row['capital_cuota'],
      'interest_amount': row['interes_cuota'],
      'total_amount': row['monto_cuota'],
      'paid_amount': row['monto_pagado'],
      'paid_principal_amount': row['capital_pagado'],
      'paid_interest_amount': row['interes_pagado'],
      'ending_balance': row['saldo_final'],
      'status': row['estado'],
      'created_at': row['fecha_creacion'],
      'updated_at': row['fecha_actualizacion'],
      'deleted_at': row['deleted_at'],
    };
  }

  Map<String, Object?> _paymentToPayload(Map<String, Object?> row) {
    return {
      'sync_id': row['sync_id'],
      'version': row['version'] ?? 1,
      'sale_sync_id': row['sale_sync_id'],
      'client_sync_id': row['client_sync_id'],
      'installment_sync_id': row['installment_sync_id'],
      'payment_date': row['fecha_pago'],
      'amount_paid': row['monto_pagado'],
      'payment_method': row['metodo_pago'],
      'payment_type': row['tipo_pago'] ?? 'cuota',
      'reference': row['referencia'],
      'year_to_pay': row['ano_a_pagar'],
      'created_at': row['fecha_creacion'],
      'updated_at': row['fecha_actualizacion'] ?? row['fecha_creacion'],
      'deleted_at': row['deleted_at'],
    };
  }
}
