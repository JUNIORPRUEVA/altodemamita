import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../../clients/data/client_repository.dart';
import '../../clients/domain/client.dart';
import '../../installments/data/installments_repository.dart';
import '../../installments/domain/installment_detail.dart';
import '../../lots/data/lot_repository.dart';
import '../../sales/data/sales_repository.dart';
import '../domain/search_result.dart';

class GlobalSearchRepository {
  GlobalSearchRepository({
    AppDatabase? appDatabase,
    ClientRepository? clientRepository,
    LotRepository? lotRepository,
    SalesRepository? salesRepository,
    InstallmentsRepository? installmentsRepository,
  })  : _appDatabase = appDatabase ?? AppDatabase.instance,
        _clientRepository =
            clientRepository ?? ClientRepository(appDatabase: appDatabase),
        _lotRepository =
            lotRepository ?? LotRepository(appDatabase: appDatabase),
        _installmentsRepository = installmentsRepository ??
            InstallmentsRepository(database: appDatabase);

  final AppDatabase _appDatabase;
  final ClientRepository _clientRepository;
  final LotRepository _lotRepository;
  final InstallmentsRepository _installmentsRepository;

  /// Búsqueda global inteligente que busca clientes y solares
  /// Retorna resultados con toda la información relacionada
  Future<List<GlobalSearchResult>> search(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final results = <GlobalSearchResult>[];

    // Buscar clientes por nombre, cédula o teléfono
    final matchingClients = await _clientRepository.fetchAll(query: query);

    for (final client in matchingClients) {
      final sales = await _getSalesForClient(client.id!);
      final installments = <InstallmentDetail>[];

      // Traer cuotas para cada venta del cliente
      for (final saleMap in sales) {
        final saleId = saleMap['id'] as int;
        final saleInstallments =
            await _installmentsRepository.getBySaleId(saleId);
        installments.addAll(saleInstallments);
      }

      final payments = <Map<String, dynamic>>[];
      for (final saleMap in sales) {
        final salePayments = await _getPaymentsForSale(saleMap['id'] as int);
        payments.addAll(salePayments);
      }

      results.add(
        GlobalSearchResult(
          client: client,
          relatedSales: sales,
          relatedInstallments: installments,
          relatedPayments: payments,
          matchType: 'client',
        ),
      );
    }

    // Buscar solares por manzana y número
    final matchingLots = await _lotRepository.fetchAll(query: query);

    for (final lot in matchingLots) {
      final sale = await _getSaleForLot(lot.id!);
      final installments = <InstallmentDetail>[];

      if (sale != null) {
        final saleInstallments =
            await _installmentsRepository.getBySaleId(sale['id'] as int);
        installments.addAll(saleInstallments);

        final payments = await _getPaymentsForSale(sale['id'] as int);

        // Traer cliente de la venta
        final clientId = sale['cliente_id'] as int;
        final clientMap = await _getClientMap(clientId);

        results.add(
          GlobalSearchResult(
            client: clientMap,
            lot: lot,
            relatedSales: [sale],
            relatedInstallments: installments,
            relatedPayments: payments,
            matchType: 'lot',
          ),
        );
      } else {
        results.add(
          GlobalSearchResult(
            lot: lot,
            relatedSales: [],
            relatedInstallments: [],
            matchType: 'lot',
          ),
        );
      }
    }

    return results;
  }

  /// Obtiene las ventas de un cliente
  Future<List<Map<String, dynamic>>> _getSalesForClient(int clientId) async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        v.*,
        u.nombre AS usuario_nombre,
        vd.nombre AS vendedor_nombre,
        vd.cedula AS vendedor_cedula,
        vd.telefono AS vendedor_telefono,
        s.manzana_numero,
        s.solar_numero
      FROM ${DatabaseSchema.salesTable} v
      LEFT JOIN ${DatabaseSchema.usersTable} u ON u.id = v.usuario_id
      LEFT JOIN ${DatabaseSchema.sellersTable} vd ON vd.id = v.vendedor_id
      LEFT JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      WHERE v.cliente_id = ?
      ORDER BY v.fecha_venta DESC, v.id DESC
      ''',
      [clientId],
    );
    return rows;
  }

  /// Obtiene la venta para un solar (si existe)
  Future<Map<String, dynamic>?> _getSaleForLot(int lotId) async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        v.*,
        u.nombre AS usuario_nombre,
        vd.nombre AS vendedor_nombre,
        vd.cedula AS vendedor_cedula,
        vd.telefono AS vendedor_telefono,
        s.manzana_numero,
        s.solar_numero
      FROM ${DatabaseSchema.salesTable} v
      LEFT JOIN ${DatabaseSchema.usersTable} u ON u.id = v.usuario_id
      LEFT JOIN ${DatabaseSchema.sellersTable} vd ON vd.id = v.vendedor_id
      LEFT JOIN ${DatabaseSchema.lotsTable} s ON s.id = v.solar_id
      WHERE v.solar_id = ?
      ORDER BY v.fecha_venta DESC, v.id DESC
      LIMIT 1
      ''',
      [lotId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Obtiene el historial de pagos para una venta
  Future<List<Map<String, dynamic>>> _getPaymentsForSale(int saleId) async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        p.id,
        p.fecha_pago,
        p.monto_pagado,
        p.metodo_pago,
        p.tipo_pago,
        p.referencia,
        p.ano_a_pagar,
        q.numero_cuota
      FROM ${DatabaseSchema.paymentsTable} p
      LEFT JOIN ${DatabaseSchema.installmentsTable} q ON q.id = p.cuota_id
      WHERE p.venta_id = ?
      ORDER BY p.fecha_pago DESC, p.id DESC
      ''',
      [saleId],
    );
    return rows;
  }

  /// Obtiene un cliente por ID
  Future<Client?> _getClientMap(int clientId) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.clientsTable,
      where: 'id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    return rows.isEmpty ? null : Client.fromMap(rows.first);
  }
}
