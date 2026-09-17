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

  /// Invalida la lista de ventas (contiene `overdueInstallmentCount` por venta).
  static Future<void> invalidateSalesList(DatabaseExecutor db) {
    return _deleteKey(db, DatabaseSchema.salesListCacheTable, salesListCacheKey);
  }

  /// Invalida el snapshot de la work queue de Pagos.
  static Future<void> invalidatePaymentsWorkQueue(DatabaseExecutor db) {
    return _deleteKey(
      db,
      DatabaseSchema.listSnapshotsTable,
      '$paymentsWorkQueueEntity:default',
    );
  }

  /// Invalida el snapshot de un listado por entidad (`clients`, `lots`, ...).
  static Future<void> invalidateListSnapshot(DatabaseExecutor db, String entity) {
    return _deleteKey(db, DatabaseSchema.listSnapshotsTable, '$entity:default');
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
