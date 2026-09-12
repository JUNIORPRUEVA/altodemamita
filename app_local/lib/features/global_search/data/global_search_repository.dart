import '../../../core/config/app_flags.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../../../core/network/backend_api_client.dart';
import '../../../core/network/backend_entity_id_registry.dart';
import '../../../models/sync/sync_status.dart';
import '../../clients/data/client_repository.dart';
import '../../clients/domain/client.dart';
import '../../installments/data/installments_repository.dart';
import '../../installments/domain/installment_detail.dart';
import '../../lots/data/lot_repository.dart';
import '../../lots/domain/lot.dart';
import '../../sales/data/sales_repository.dart';
import '../domain/search_result.dart';

class GlobalSearchRepository {
  GlobalSearchRepository({
    AppDatabase? appDatabase,
    ClientRepository? clientRepository,
    LotRepository? lotRepository,
    SalesRepository? salesRepository,
    InstallmentsRepository? installmentsRepository,
    BackendApiClient? apiClient,
  }) : _appDatabase = appDatabase ?? AppDatabase.instance,
       _clientRepository =
           clientRepository ?? ClientRepository(appDatabase: appDatabase),
       _lotRepository =
           lotRepository ?? LotRepository(appDatabase: appDatabase),
       _installmentsRepository =
           installmentsRepository ??
           InstallmentsRepository(database: appDatabase),
       _apiClient = apiClient ?? BackendApiClient();

  final AppDatabase _appDatabase;
  final ClientRepository _clientRepository;
  final LotRepository _lotRepository;
  final InstallmentsRepository _installmentsRepository;
  final BackendApiClient _apiClient;
  final BackendEntityIdRegistry _idRegistry = BackendEntityIdRegistry.instance;

  bool get _useBackendMode => cloudCutoverMode.usesAuthoritativeBusinessWrites;

  /// Búsqueda global inteligente que busca clientes y solares
  /// Retorna resultados con toda la información relacionada
  Future<List<GlobalSearchResult>> search(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }

    if (_useBackendMode) {
      return _searchFromBackend(query);
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
        final saleInstallments = await _installmentsRepository.getBySaleId(
          saleId,
        );
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
        final saleInstallments = await _installmentsRepository.getBySaleId(
          sale['id'] as int,
        );
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

  // =====================================================================
  // Rama CLOUD_AUTHORITATIVE: PostgreSQL es la autoridad.
  // En línea el historial del cliente (ventas/cuotas/pagos/solares) viene
  // del backend (`/owner/clients/:clientId`), NUNCA de joins SQLite con ids
  // locales que no coinciden con los ids sintéticos cloud.
  // =====================================================================

  Future<List<GlobalSearchResult>> _searchFromBackend(String query) async {
    final results = <GlobalSearchResult>[];

    final matchingClients = await _clientRepository.fetchAll(query: query);
    for (final client in matchingClients) {
      results.add(await _clientCloudResult(client));
    }

    final matchingLots = await _lotRepository.fetchAll(query: query);
    for (final lot in matchingLots) {
      final result = await _lotCloudResult(lot);
      if (result != null) {
        results.add(result);
      }
    }

    return results;
  }

  Future<GlobalSearchResult> _clientCloudResult(Client client) async {
    final remoteClientId = _resolveRemoteClientId(client);
    if (remoteClientId == null) {
      return GlobalSearchResult(client: client, matchType: 'client');
    }

    try {
      final response = await _apiClient.get('/owner/clients/$remoteClientId');
      final data = _dataOf(response);
      if (data.isEmpty) {
        return GlobalSearchResult(client: client, matchType: 'client');
      }
      return _resultFromClientDetailData(data, client);
    } catch (_) {
      // Continuidad: si el backend no responde mostramos al menos al cliente.
      return GlobalSearchResult(client: client, matchType: 'client');
    }
  }

  Future<GlobalSearchResult?> _lotCloudResult(Lot lot) async {
    final remoteLotId = _resolveRemoteLotId(lot);
    if (remoteLotId == null) {
      return GlobalSearchResult(lot: lot, matchType: 'lot');
    }

    try {
      final listResponse = await _apiClient.get(
        '/owner/sales',
        queryParameters: {'page': '1', 'pageSize': '200', 'lotId': remoteLotId},
      );
      final items = _listOfMaps(_dataOf(listResponse)['items']);
      if (items.isEmpty) {
        return GlobalSearchResult(lot: lot, matchType: 'lot');
      }

      final firstSale = items.first;
      final saleRemoteId = _text(firstSale['id']).trim();
      final clientEntity = _mapOf(firstSale['clientEntity']);
      final clientRemoteId = _text(clientEntity['id']).trim();
      if (saleRemoteId.isEmpty || clientRemoteId.isEmpty) {
        return GlobalSearchResult(lot: lot, matchType: 'lot');
      }

      final detailResponse = await _apiClient.get(
        '/owner/clients/$clientRemoteId',
      );
      final data = _dataOf(detailResponse);
      if (data.isEmpty) {
        return GlobalSearchResult(lot: lot, matchType: 'lot');
      }

      final client = _clientFromCloudEntity(clientEntity);
      return _resultFromClientDetailData(
        data,
        client,
        lot: lot,
        onlySaleId: saleRemoteId,
      );
    } catch (_) {
      return GlobalSearchResult(lot: lot, matchType: 'lot');
    }
  }

  GlobalSearchResult _resultFromClientDetailData(
    Map<String, dynamic> data,
    Client client, {
    Lot? lot,
    String? onlySaleId,
  }) {
    final salesJson = _listOfMaps(data['sales']);
    final sales = <Map<String, dynamic>>[];
    final installments = <InstallmentDetail>[];
    final payments = <Map<String, dynamic>>[];

    for (final saleJson in salesJson) {
      final saleId = _text(saleJson['id']).trim();
      if (onlySaleId != null && saleId != onlySaleId) {
        continue;
      }
      final saleLocal = _saleLocalMap(saleJson, client);
      sales.add(saleLocal);
      installments.addAll(_installmentsLocalList(saleJson, client, saleLocal));
      payments.addAll(_paymentsLocalList(saleJson, saleLocal));
    }

    return GlobalSearchResult(
      client: client,
      lot: lot,
      relatedSales: sales,
      relatedInstallments: installments,
      relatedPayments: payments,
      matchType: lot != null ? 'lot' : 'client',
    );
  }

  Map<String, dynamic> _saleLocalMap(Map<String, dynamic> sale, Client client) {
    final remoteSaleId = _text(sale['id']).trim();
    final localSaleId = remoteSaleId.isEmpty
        ? 0
        : _idRegistry.register('sales', remoteSaleId);
    final lot = _mapOf(sale['lot']);
    final status = _text(sale['status']).trim().toLowerCase();
    final deadline = _text(sale['initialPaymentDeadline']);
    final reservationMinimum = _nullableDouble(
      sale['reservationMinimumAmount'],
    );
    return {
      'id': localSaleId,
      'sync_id': _text(sale['syncId']),
      'id_remote': remoteSaleId,
      'cliente_id': client.id ?? 0,
      'estado': status.isEmpty ? 'desconocido' : status,
      'fecha_venta': _text(sale['saleDate']),
      'fecha_creacion': _text(sale['createdAt']),
      'usuario_nombre': _text(sale['operatorUserName']),
      'vendedor_nombre': _text(sale['sellerName']),
      'manzana_numero': _text(lot['block']),
      'solar_numero': _text(lot['number']),
      'solar_id': 0,
      'precio_venta': _doubleOf(sale['total']),
      'monto_inicial_requerido': _doubleOf(sale['initialRequiredAmount']),
      'monto_inicial_pagado': _doubleOf(sale['initialPaid']),
      'monto_inicial_pendiente': _doubleOf(sale['initialPendingAmount']),
      'monto_apartado_minimo': reservationMinimum,
      'monto_apartado_pagado': _doubleOf(sale['reservationPaidAmount']),
      'fecha_limite_inicial': deadline.isEmpty ? null : deadline,
      'saldo_financiado': _doubleOf(sale['financedBalance']),
      'saldo_pendiente': _doubleOf(sale['balance']),
      'interes_mensual': _doubleOf(sale['monthlyInterestRate']),
      'cantidad_cuotas': _intOf(sale['installmentCount']),
    };
  }

  List<InstallmentDetail> _installmentsLocalList(
    Map<String, dynamic> sale,
    Client client,
    Map<String, dynamic> saleLocal,
  ) {
    final lotCode = _lotCodeFromLocalSale(saleLocal);
    return _listOfMaps(sale['installments'])
        .map((installment) {
          final remoteId = _text(installment['id']).trim();
          final localId = remoteId.isEmpty
              ? 0
              : _idRegistry.register('installments', remoteId);
          final total = _doubleOf(installment['amount']);
          final paid = _doubleOf(installment['paidAmount']);
          final remaining = total - paid;
          return InstallmentDetail(
            id: localId,
            installmentNumber: _intOf(installment['installmentNumber']),
            saleId: (saleLocal['id'] as num?)?.toInt() ?? 0,
            clientName: client.fullName,
            clientDocumentId: client.documentId,
            lotCode: lotCode,
            dueDate:
                DateTime.tryParse(_text(installment['dueDate'])) ??
                DateTime.now(),
            openingBalance: _doubleOf(installment['openingBalance']),
            principalAmount: _doubleOf(installment['principalAmount']),
            interestAmount: _doubleOf(installment['interestAmount']),
            totalAmount: total,
            paidAmount: paid,
            remainingAmount: remaining < 0 ? 0 : remaining,
            endingBalance: _doubleOf(installment['endingBalance']),
            status: _text(installment['status']).isEmpty
                ? 'pendiente'
                : _text(installment['status']),
          );
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _paymentsLocalList(
    Map<String, dynamic> sale,
    Map<String, dynamic> saleLocal,
  ) {
    final installmentNumberByRemoteId = <String, int>{};
    for (final installment in _listOfMaps(sale['installments'])) {
      final id = _text(installment['id']).trim();
      if (id.isNotEmpty) {
        installmentNumberByRemoteId[id] = _intOf(
          installment['installmentNumber'],
        );
      }
    }
    final installmentSyncByRemoteId = <String, int>{};
    for (final installment in _listOfMaps(sale['installments'])) {
      final id = _text(installment['id']).trim();
      final syncId = _text(installment['syncId']).trim();
      if (syncId.isNotEmpty && installmentNumberByRemoteId[id] != null) {
        installmentSyncByRemoteId[syncId] = installmentNumberByRemoteId[id]!;
      }
    }

    return _listOfMaps(sale['payments'])
        .map((payment) {
          final installmentId = _text(payment['installmentId']).trim();
          final installmentSyncId = _text(payment['installmentSyncId']).trim();
          final numeroCuota =
              installmentNumberByRemoteId[installmentId] ??
              installmentSyncByRemoteId[installmentSyncId];
          final yearToPay = _intOf(payment['yearToPay']);
          return {
            'fecha_pago': _text(payment['paidAt']),
            'monto_pagado': _doubleOf(payment['amount']),
            'metodo_pago': _text(payment['method']),
            'tipo_pago': _localPaymentType(
              payment,
              hasLinkedInstallment:
                  installmentId.isNotEmpty || installmentSyncId.isNotEmpty,
            ),
            'referencia': _text(payment['reference']),
            'numero_cuota': numeroCuota,
            'ano_a_pagar': yearToPay <= 0 ? null : yearToPay,
          };
        })
        .toList(growable: false);
  }

  String _localPaymentType(
    Map<String, dynamic> payment, {
    required bool hasLinkedInstallment,
  }) {
    switch (_text(payment['paymentType']).trim().toLowerCase()) {
      case 'apartado':
      case 'reservation':
      case 'reserve':
        return 'apartado';
      case 'initial':
      case 'inicial':
      case 'down_payment':
      case 'abono_inicial':
        return 'abono_inicial';
      case 'installment':
      case 'cuota':
        return 'cuota';
      case 'extra':
      case 'capital':
      case 'abono_capital':
        return 'abono_capital';
      case 'liquidacion_total':
      case 'settlement':
      case 'total_settlement':
        return 'liquidacion_total';
      case 'contado':
      case 'cash':
      case 'cash_sale':
        return 'contado';
      default:
        return hasLinkedInstallment ? 'cuota' : 'pago';
    }
  }

  String? _resolveRemoteClientId(Client client) {
    if (client.id != null) {
      final remote = _idRegistry.resolveRemoteId('clients', client.id);
      if (remote != null && remote.isNotEmpty) {
        return remote;
      }
    }
    final syncId = client.syncId?.trim();
    if (syncId != null && syncId.isNotEmpty) {
      return syncId;
    }
    return null;
  }

  String? _resolveRemoteLotId(Lot lot) {
    if (lot.id == null) {
      return null;
    }
    for (final namespace in ['lots', 'products']) {
      final remote = _idRegistry.resolveRemoteId(namespace, lot.id);
      if (remote != null && remote.isNotEmpty) {
        return remote;
      }
    }
    return null;
  }

  Client _clientFromCloudEntity(Map<String, dynamic> entity) {
    final now = DateTime.now();
    final remoteId = _text(entity['id']).trim();
    final syncId = _text(entity['syncId']).trim();
    return Client(
      id: remoteId.isEmpty ? null : _idRegistry.register('clients', remoteId),
      syncId: syncId.isEmpty ? remoteId : syncId,
      fullName: _text(entity['name']),
      documentId: _text(entity['document']),
      phone: _nullableText(entity['phone']),
      address: _nullableText(entity['address']),
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.synced,
    );
  }

  String _lotCodeFromLocalSale(Map<String, dynamic> saleLocal) {
    final block = _text(saleLocal['manzana_numero']);
    final number = _text(saleLocal['solar_numero']);
    if (block.isNotEmpty || number.isNotEmpty) {
      return 'M$block-S$number';
    }
    return '';
  }

  Map<String, dynamic> _dataOf(Object? response) {
    final payload = _mapOf(response);
    final data = payload['data'];
    return data is Map ? _mapOf(data) : payload;
  }

  Map<String, dynamic> _mapOf(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, data) => MapEntry(key.toString(), data));
    }
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _listOfMaps(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((item) => _mapOf(item))
        .toList(growable: false);
  }

  String _text(Object? value) => value?.toString().trim() ?? '';

  String? _nullableText(Object? value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }

  double _doubleOf(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double? _nullableDouble(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    if (text.isEmpty) {
      return null;
    }
    return double.tryParse(text);
  }

  int _intOf(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
