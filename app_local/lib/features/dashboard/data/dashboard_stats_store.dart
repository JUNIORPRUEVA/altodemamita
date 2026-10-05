import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/cloud_foundation/sales_cache_invalidation.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../../../core/resilience/app_storage_namespace.dart';
import '../../clients/data/client_repository.dart';
import '../../installments/data/installments_repository.dart';
import '../../lots/data/lot_repository.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/sale_summary.dart';

/// KPIs del resumen principal (RESUMEN / REPORTES).
///
/// Es un READ MODEL: no es la autoridad financiera (PostgreSQL lo es), solo el
/// último estado calculado desde la base local para pintar de inmediato.
class DashboardStats {
  const DashboardStats({
    required this.totalClients,
    required this.totalLots,
    required this.availableLots,
    required this.soldLots,
    required this.pendingPayments,
    required this.incompleteInitialPayments,
    required this.overduePayments,
    required this.activeFinancing,
    required this.portfolioPendingAmount,
    required this.collectedAmount,
    required this.soldAmount,
  });

  const DashboardStats.empty()
    : totalClients = 0,
      totalLots = 0,
      availableLots = 0,
      soldLots = 0,
      pendingPayments = 0,
      incompleteInitialPayments = 0,
      overduePayments = 0,
      activeFinancing = 0,
      portfolioPendingAmount = 0,
      collectedAmount = 0,
      soldAmount = 0;

  final int totalClients;
  final int totalLots;
  final int availableLots;
  final int soldLots;
  final int pendingPayments;
  final int incompleteInitialPayments;
  final int overduePayments;
  final int activeFinancing;
  final double portfolioPendingAmount;
  final double collectedAmount;
  final double soldAmount;

  /// Serializacion para el snapshot persistido. Solo numeros: el snapshot debe
  /// poder leerse sin tocar SQLite.
  Map<String, Object?> toJson() => <String, Object?>{
    'totalClients': totalClients,
    'totalLots': totalLots,
    'availableLots': availableLots,
    'soldLots': soldLots,
    'pendingPayments': pendingPayments,
    'incompleteInitialPayments': incompleteInitialPayments,
    'overduePayments': overduePayments,
    'activeFinancing': activeFinancing,
    'portfolioPendingAmount': portfolioPendingAmount,
    'collectedAmount': collectedAmount,
    'soldAmount': soldAmount,
  };

  /// Devuelve `null` ante cualquier JSON invalido o incompleto: un snapshot
  /// corrupto NUNCA debe romper la pantalla ni mostrar ceros falsos.
  static DashboardStats? fromJson(Object? raw) {
    final map = raw is String ? (jsonDecode(raw) as Object?) : raw;
    if (map is! Map) {
      return null;
    }
    int? asInt(String key) {
      final value = map[key];
      if (value is num) {
        return value.toInt();
      }
      return null;
    }

    double? asDouble(String key) {
      final value = map[key];
      if (value is num) {
        return value.toDouble();
      }
      return null;
    }

    final totalClients = asInt('totalClients');
    final totalLots = asInt('totalLots');
    final availableLots = asInt('availableLots');
    final soldLots = asInt('soldLots');
    final pendingPayments = asInt('pendingPayments');
    final incompleteInitialPayments = asInt('incompleteInitialPayments');
    final overduePayments = asInt('overduePayments');
    final activeFinancing = asInt('activeFinancing');
    final portfolioPendingAmount = asDouble('portfolioPendingAmount');
    final collectedAmount = asDouble('collectedAmount');
    final soldAmount = asDouble('soldAmount');
    if (totalClients == null ||
        totalLots == null ||
        availableLots == null ||
        soldLots == null ||
        pendingPayments == null ||
        incompleteInitialPayments == null ||
        overduePayments == null ||
        activeFinancing == null ||
        portfolioPendingAmount == null ||
        collectedAmount == null ||
        soldAmount == null) {
      return null;
    }
    return DashboardStats(
      totalClients: totalClients,
      totalLots: totalLots,
      availableLots: availableLots,
      soldLots: soldLots,
      pendingPayments: pendingPayments,
      incompleteInitialPayments: incompleteInitialPayments,
      overduePayments: overduePayments,
      activeFinancing: activeFinancing,
      portfolioPendingAmount: portfolioPendingAmount,
      collectedAmount: collectedAmount,
      soldAmount: soldAmount,
    );
  }
}

/// Calcula los KPIs del resumen desde la base LOCAL (read model).
///
/// Se extrajo de la pantalla para poder medirlo y testearlo sin UI.
Future<DashboardStats> computeDashboardStats({
  required ClientRepository clientRepository,
  required LotRepository lotRepository,
  required SalesRepository salesRepository,
  required InstallmentsRepository installmentsRepository,
}) async {
  final List<dynamic> results;
  try {
    results = await Future.wait<dynamic>([
      clientRepository.countAll(),
      lotRepository.countAll(),
      lotRepository.countByStatus('disponible'),
      lotRepository.countByStatus('vendido'),
      salesRepository.fetchAll(),
      installmentsRepository.getAll(),
    ]);
  } catch (_) {
    return _computeDashboardStatsFromLocalSqlite();
  }

  final sales = results[4] as List<SaleSummary>;
  final installments = results[5] as List<dynamic>;

  final pendingPayments = installments
      .where((item) => item.calculatedStatus != 'pagada')
      .length;
  final overduePayments = installments
      .where((item) => item.calculatedStatus == 'vencida')
      .length;
  final incompleteInitialPayments = sales
      .where((sale) => sale.pendingInitialPayment > 0.009)
      .length;
  final activeFinancing = sales
      .where((sale) => sale.status == 'activa' && sale.pendingBalance > 0.009)
      .length;
  final portfolioPendingAmount = sales.fold<double>(
    0,
    (total, sale) => total + sale.pendingInitialPayment + sale.pendingBalance,
  );
  final collectedAmount = sales.fold<double>(
    0,
    (total, sale) =>
        total +
        sale.paidInitialPayment +
        (sale.salePrice - sale.pendingBalance - sale.downPaymentAmount),
  );
  final soldAmount = sales.fold<double>(
    0,
    (total, sale) => total + sale.salePrice,
  );

  return DashboardStats(
    totalClients: results[0] as int,
    totalLots: results[1] as int,
    availableLots: results[2] as int,
    soldLots: results[3] as int,
    pendingPayments: pendingPayments,
    incompleteInitialPayments: incompleteInitialPayments,
    overduePayments: overduePayments,
    activeFinancing: activeFinancing,
    portfolioPendingAmount: portfolioPendingAmount,
    collectedAmount: collectedAmount,
    soldAmount: soldAmount,
  );
}

Future<DashboardStats> _computeDashboardStatsFromLocalSqlite() async {
  final db = await AppDatabase.instance.database;
  final today = DateTime.now().toIso8601String();

  Future<int> intValue(String sql, [List<Object?> args = const []]) async {
    final rows = await db.rawQuery(sql, args);
    if (rows.isEmpty) {
      return 0;
    }
    return (rows.first.values.first as num?)?.toInt() ?? 0;
  }

  Future<double> doubleValue(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    final rows = await db.rawQuery(sql, args);
    if (rows.isEmpty) {
      return 0;
    }
    return (rows.first.values.first as num?)?.toDouble() ?? 0;
  }

  final totalClients = await intValue(
    'SELECT COUNT(*) FROM ${DatabaseSchema.clientsTable} '
    'WHERE deleted_at IS NULL',
  );
  final totalLots = await intValue(
    'SELECT COUNT(*) FROM ${DatabaseSchema.lotsTable} WHERE deleted_at IS NULL',
  );
  final availableLots = await intValue(
    'SELECT COUNT(*) FROM ${DatabaseSchema.lotsTable} '
    "WHERE deleted_at IS NULL AND estado = 'disponible'",
  );
  final soldLots = await intValue(
    'SELECT COUNT(*) FROM ${DatabaseSchema.lotsTable} '
    "WHERE deleted_at IS NULL AND estado = 'vendido'",
  );
  final pendingPayments = await intValue(
    'SELECT COUNT(*) FROM ${DatabaseSchema.installmentsTable} q '
    'INNER JOIN ${DatabaseSchema.salesTable} v ON v.id = q.venta_id '
    'WHERE q.deleted_at IS NULL AND v.deleted_at IS NULL '
    "AND q.estado NOT IN ('pagada', 'ajustada', 'cancelada') "
    'AND (q.monto_cuota - COALESCE(q.monto_pagado, 0)) > 0.009',
  );
  final overduePayments = await intValue(
    'SELECT COUNT(*) FROM ${DatabaseSchema.installmentsTable} q '
    'INNER JOIN ${DatabaseSchema.salesTable} v ON v.id = q.venta_id '
    'WHERE q.deleted_at IS NULL AND v.deleted_at IS NULL '
    "AND q.estado NOT IN ('pagada', 'ajustada', 'cancelada') "
    'AND (q.monto_cuota - COALESCE(q.monto_pagado, 0)) > 0.009 '
    'AND q.fecha_vencimiento < ?',
    [today],
  );
  final incompleteInitialPayments = await intValue(
    'SELECT COUNT(*) FROM ${DatabaseSchema.salesTable} '
    'WHERE deleted_at IS NULL AND monto_inicial_pendiente > 0.009',
  );
  final activeFinancing = await intValue(
    'SELECT COUNT(*) FROM ${DatabaseSchema.salesTable} '
    "WHERE deleted_at IS NULL AND estado = 'activa' "
    'AND saldo_pendiente > 0.009',
  );
  final portfolioPendingAmount = await doubleValue(
    'SELECT COALESCE(SUM(monto_inicial_pendiente + saldo_pendiente), 0) '
    'FROM ${DatabaseSchema.salesTable} WHERE deleted_at IS NULL',
  );
  final collectedAmount = await doubleValue(
    'SELECT COALESCE(SUM(monto_inicial_pagado + '
    'MAX(precio_venta - saldo_pendiente - inicial_monto, 0)), 0) '
    'FROM ${DatabaseSchema.salesTable} WHERE deleted_at IS NULL',
  );
  final soldAmount = await doubleValue(
    'SELECT COALESCE(SUM(precio_venta), 0) '
    'FROM ${DatabaseSchema.salesTable} WHERE deleted_at IS NULL',
  );

  return DashboardStats(
    totalClients: totalClients,
    totalLots: totalLots,
    availableLots: availableLots,
    soldLots: soldLots,
    pendingPayments: pendingPayments,
    incompleteInitialPayments: incompleteInitialPayments,
    overduePayments: overduePayments,
    activeFinancing: activeFinancing,
    portfolioPendingAmount: portfolioPendingAmount,
    collectedAmount: collectedAmount,
    soldAmount: soldAmount,
  );
}

/// Snapshot COMPARTIDO del resumen.
///
/// POR QUÉ EXISTE
/// `_buildCurrentPage()` del shell **reconstruye el widget** cada vez que se
/// cambia de módulo, así que un snapshot guardado en el `State` de la pantalla
/// muere al salir y volver. Este store vive fuera de la pantalla, por lo que el
/// resumen se puede pintar inmediatamente al volver (sin spinner) y refrescar
/// después en background.
///
/// Es solo UX/read model: nunca sustituye a la nube como autoridad.
class DashboardStatsStore extends ChangeNotifier {
  DashboardStatsStore._() {
    // Cableado real de invalidación: cualquier operación financiera o descarga
    // de nube pasa por `SalesCacheInvalidation` (pago, venta, anulación,
    // settlement, cloud download), que publica una nueva revisión.
    SalesCacheInvalidation.revision.addListener(invalidate);
  }

  static final DashboardStatsStore instance = DashboardStatsStore._();

  /// Edad máxima antes de considerar el snapshot "viejo".
  ///
  /// Evita que tres entradas consecutivas disparen tres refrescos seguidos.
  static const Duration refreshInterval = Duration(seconds: 15);

  /// Clave del snapshot persistido (fuera de SQLite).
  ///
  /// POR QUÉ: si el sync tiene tomado SQLite (writer WAL), un snapshot que solo
  /// viva en memoria obliga a esperar 1-2 minutos en la primera entrada. En
  /// disco se lee en milisegundos y NO compite con el writer.
  static const String persistedKey = 'dashboard.stats.snapshot.v1';

  /// Snapshot + fecha de guardado persistidos juntos.
  static const String _persistedSavedAtSuffix = '.savedAt';

  static final String _scopedPersistedKey = AppStorageNamespace.scopedKey(
    persistedKey,
  );

  static final String _scopedSavedAtKey = AppStorageNamespace.scopedKey(
    '$persistedKey$_persistedSavedAtSuffix',
  );

  DashboardStats? _stats;
  DateTime? _loadedAt;
  bool _refreshing = false;
  bool _hydrateAttempted = false;

  DashboardStats? get stats => _stats;

  DateTime? get loadedAt => _loadedAt;

  bool get isRefreshing => _refreshing;

  /// `true` cuando hay snapshot utilizable para pintar de inmediato.
  bool get hasSnapshot => _stats != null;

  /// `true` cuando ya se intentó leer el snapshot persistido.
  bool get hydrateAttempted => _hydrateAttempted;

  /// Lee el snapshot persistido (SharedPreferences) y lo deja disponible para
  /// pintar ANTES de tocar SQLite.
  ///
  /// Es idempotente: sólo lee una vez por proceso salvo [force]. Nunca lanza,
  /// así que no puede retrasar ni romper el arranque de la pantalla.
  Future<void> hydrateFromDisk({bool force = false}) async {
    if (_hydrateAttempted && !force) {
      return;
    }
    _hydrateAttempted = true;
    if (_stats != null) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_scopedPersistedKey);
      if (raw == null || raw.trim().isEmpty) {
        return;
      }
      final parsed = DashboardStats.fromJson(raw);
      if (parsed == null) {
        return;
      }
      _stats = parsed;
      // Se conserva la fecha REAL de guardado: si es viejo, `needsRefresh`
      // pide el refresco en background igualmente.
      _loadedAt = DateTime.tryParse(prefs.getString(_scopedSavedAtKey) ?? '');
      notifyListeners();
    } catch (_) {
      // Best-effort: sin snapshot persistido se cae al cálculo local normal.
    }
  }

  void _persistBestEffort(DashboardStats stats, DateTime savedAt) {
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_scopedPersistedKey, jsonEncode(stats.toJson()));
        await prefs.setString(_scopedSavedAtKey, savedAt.toIso8601String());
      } catch (_) {
        // Best-effort: persistir es una optimización de UX, no un requisito.
      }
    }());
  }

  void _removePersistedBestEffort() {
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_scopedPersistedKey);
        await prefs.remove(_scopedSavedAtKey);
      } catch (_) {
        // Best-effort.
      }
    }());
  }

  /// `true` cuando conviene refrescar en background.
  bool get needsRefresh {
    if (_stats == null) {
      return true;
    }
    final loadedAt = _loadedAt;
    if (loadedAt == null) {
      return true;
    }
    // Cambio de día: los KPIs dependen de la fecha (vencidas).
    final now = DateTime.now();
    if (loadedAt.year != now.year ||
        loadedAt.month != now.month ||
        loadedAt.day != now.day) {
      return true;
    }
    return now.difference(loadedAt) >= refreshInterval;
  }

  void markRefreshing(bool value) {
    if (_refreshing == value) {
      return;
    }
    _refreshing = value;
    notifyListeners();
  }

  void save(DashboardStats stats) {
    final savedAt = DateTime.now();
    _stats = stats;
    _loadedAt = savedAt;
    _refreshing = false;
    notifyListeners();
    _persistBestEffort(stats, savedAt);
  }

  /// Fuerza que el próximo acceso refresque (pago, venta, anulación, etc.).
  ///
  /// NO borra el snapshot visible: invalida = marcar stale + refresh background.
  void invalidate() {
    _loadedAt = null;
    notifyListeners();
  }

  /// Limpia el snapshot en memoria y el persistido. Se usa solo si los datos
  /// locales dejan de ser válidos (p. ej. cierre de sesión).
  void clear() {
    _stats = null;
    _loadedAt = null;
    _hydrateAttempted = false;
    notifyListeners();
    _removePersistedBestEffort();
  }

  /// Sembrado de snapshot para pruebas.
  @visibleForTesting
  void debugSeed(DashboardStats? stats, {DateTime? loadedAt}) {
    _stats = stats;
    _loadedAt = loadedAt;
  }

  /// Marca que la hidratación ya ocurrió (pruebas).
  @visibleForTesting
  void debugMarkHydrated() {
    _hydrateAttempted = true;
  }
}

/// Evita que dos entradas rápidas al Resumen disparen dos cálculos simultáneos.
class DashboardRefreshGuard {
  DashboardRefreshGuard._();

  static Future<void>? _inFlight;

  static bool get isRunning => _inFlight != null;

  static Future<void> run(Future<void> Function() task) {
    final current = _inFlight;
    if (current != null) {
      return current;
    }
    final future = task().whenComplete(() {
      _inFlight = null;
    });
    _inFlight = future;
    return future;
  }
}
