import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/database_schema.dart';

/// Invalidación COMPARTIDA de las caches derivadas de ventas y cuotas.
///
/// POR QUÉ EXISTE
/// `overdueInstallmentCount` y los saldos que muestra la lista de ventas son
/// valores DERIVADOS: cambian al registrar/anular un pago, al liquidar (o anular
/// la liquidación), al recibir cuotas nuevas desde la nube y al cambiar el día de
/// negocio. Si la lista se sirve de un snapshot viejo, el operador ve un conteo
/// incorrecto aunque la base local ya esté bien.
///
/// Es el ÚNICO punto de invalidación, de modo que ningún repositorio necesita
/// tocar métodos privados de otro (p. ej. Pagos no accede a internals de Ventas).
///
/// Sólo se cachean NÚMEROS (`overdueInstallmentCount`); el texto
/// ("2 cuotas vencidas") lo genera la UI a partir del entero.
class SalesCacheInvalidation {
  const SalesCacheInvalidation._();

  /// Clave del snapshot de la lista de ventas.
  static const String salesListCacheKey = 'default';

  /// Entidad del snapshot de la work queue de Pagos.
  static const String paymentsWorkQueueEntity = 'payments-work-queue';

  /// Entidades cuyo cambio afecta al conteo de vencidas / saldos de la lista.
  static const Set<String> financialScopes = {'sales', 'installments', 'payments'};

  /// Scopes que alimentan los KPIs del Resumen aunque NO tengan cache propia en
  /// la base.
  ///
  /// Los nombres son los scopes REALES de descarga de nube
  /// (`sync_manager._businessHydrationScopes`): los solares/lotes viajan bajo
  /// el scope `products` (`products_sync_repository.dart`).
  ///
  /// `clients` y `products` cambian "98 clientes" y "143 solares": no hay fila
  /// de cache que borrar, pero el snapshot del Resumen sí queda viejo.
  static const Set<String> dashboardReadModelScopes = {
    'clients',
    'products',
    'sales',
    'installments',
    'payments',
  };

  /// Marca el snapshot del Resumen como vencido SIN borrar ninguna cache.
  ///
  /// Se usa cuando el cambio no tiene fila de cache que eliminar (clientes,
  /// solares) pero altera los KPIs mostrados.
  static void notifyReadModelChanged() {
    _notifyRevision();
  }

  /// Aplica la invalidación correcta tras DESCARGAR registros de la nube.
  ///
  /// Único punto de decisión, para que la política sea testeable y no viva
  /// enterrada dentro del bucle de descarga:
  /// * `records <= 0` → no invalida nada (descarga vacía no cambia KPIs).
  /// * scope financiero → borra las caches derivadas (ventas / cola de pagos).
  /// * scope que alimenta el Resumen → marca el snapshot como vencido.
  /// * scope irrelevante (permisos, roles, usuarios) → no toca nada.
  static Future<void> onCloudRecordsApplied(
    DatabaseExecutor db, {
    required String scope,
    required int records,
  }) async {
    if (records <= 0) {
      return;
    }
    if (financialScopes.contains(scope)) {
      await invalidateFinancialDerivedCaches(db);
      return;
    }
    if (dashboardReadModelScopes.contains(scope)) {
      notifyReadModelChanged();
    }
  }

  /// Revisión global de caches financieras derivadas.
  ///
  /// Permite que read models que NO viven en la base (p. ej. el snapshot del
  /// Resumen) se enteren de que hubo un pago, una venta, una anulación, un
  /// settlement o una descarga de nube, sin que `core` dependa de las features.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void _notifyRevision() {
    revision.value = revision.value + 1;
  }

  /// Invalida la lista de ventas (contiene `overdueInstallmentCount` por venta).
  static Future<void> invalidateSalesList(DatabaseExecutor db) async {
    await _deleteKey(
      db,
      DatabaseSchema.salesListCacheTable,
      salesListCacheKey,
    );
    _notifyRevision();
  }

  /// Invalida el snapshot de la work queue de Pagos.
  static Future<void> invalidatePaymentsWorkQueue(DatabaseExecutor db) async {
    await _deleteKey(
      db,
      DatabaseSchema.listSnapshotsTable,
      '$paymentsWorkQueueEntity:default',
    );
    _notifyRevision();
  }

  /// Invalida el snapshot de un listado por entidad (`clients`, `lots`, ...).
  static Future<void> invalidateListSnapshot(
    DatabaseExecutor db,
    String entity,
  ) async {
    await _deleteKey(
      db,
      DatabaseSchema.listSnapshotsTable,
      '$entity:default',
    );
    _notifyRevision();
  }

  /// Invalida lo derivado de una operación FINANCIERA:
  /// lista de ventas + work queue de pagos.
  static Future<void> invalidateFinancialDerivedCaches(DatabaseExecutor db) async {
    await invalidateSalesList(db);
    await invalidatePaymentsWorkQueue(db);
  }

  /// Invalida todas las caches de listado. Se usa cuando una descarga de la nube
  /// puede haber cambiado varias entidades a la vez.
  static Future<void> invalidateAllListCaches(DatabaseExecutor db) async {
    await _safe(() => db.delete(DatabaseSchema.salesListCacheTable));
    await _safe(() => db.delete(DatabaseSchema.listSnapshotsTable));
  }

  static Future<void> _deleteKey(
    DatabaseExecutor db,
    String table,
    String key,
  ) async {
    await _safe(
      () => db.delete(table, where: 'cache_key = ?', whereArgs: [key]),
    );
  }

  static Future<void> _safe(Future<Object?> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Best-effort: un fallo de cache NUNCA debe romper una operación
      // financiera ni propagar un error al usuario.
    }
  }
}
