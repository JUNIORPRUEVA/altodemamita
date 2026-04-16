import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Service to manage debug test data for development and testing purposes.
/// All test data is marked with special identifiers to enable easy toggling.
import '../../features/sales/domain/sale_calculator.dart';

class DebugTestDataService {
  // Test data prefixes to easily identify and remove test data
  static const String _testCedulaPrefix = '999-';
  static const String _testClientPrefix = '[TEST] ';
  static const String _testSellerPrefix = '[TEST] ';
  static const String _testLotPrefix = 'TEST-';

  /// Seed all test data into the database
  static Future<void> seedTestData(Database db) async {
    try {
      await db.transaction((txn) async {
        // Insert test clients
        final clientIds = await _insertTestClients(txn);

        // Insert test sellers
        final sellerIds = await _insertTestSellers(txn);

        // Insert test lots
        final lotIds = await _insertTestLots(txn);

        // Insert test sales (with activation)
        final saleIds =
            await _insertTestSales(txn, clientIds, sellerIds, lotIds);

        // Insert test payments
        await _insertTestPayments(txn, saleIds);
      });
    } catch (e) {
      print('Error seeding test data: $e');
      rethrow;
    }
  }

  /// Clear all test data from the database
  static Future<void> clearTestData(Database db) async {
    try {
      await db.transaction((txn) async {
        // Delete in order of foreign key dependencies

        // Delete test payments
        await txn.delete(
          'pagos',
          where: 'venta_id IN (SELECT id FROM ventas WHERE cliente_id IN '
              '(SELECT id FROM clientes WHERE cedula LIKE ?))',
          whereArgs: ['$_testCedulaPrefix%'],
        );

        // Delete test installments (cascade deleted with sales, but just to be sure)
        await txn.delete(
          'cuotas',
          where: 'venta_id IN (SELECT id FROM ventas WHERE cliente_id IN '
              '(SELECT id FROM clientes WHERE cedula LIKE ?))',
          whereArgs: ['$_testCedulaPrefix%'],
        );

        // Delete test sales
        await txn.delete(
          'ventas',
          where: 'cliente_id IN (SELECT id FROM clientes WHERE cedula LIKE ?)',
          whereArgs: ['$_testCedulaPrefix%'],
        );

        // Reset lot status from test sales
        await txn.update(
          'solares',
          {'estado': 'disponible'},
          where: 'manzana_numero LIKE ?',
          whereArgs: ['$_testLotPrefix%'],
        );

        // Delete test lots
        await txn.delete(
          'solares',
          where: 'manzana_numero LIKE ?',
          whereArgs: ['$_testLotPrefix%'],
        );

        // Delete test sellers
        await txn.delete(
          'vendedores',
          where: 'cedula LIKE ?',
          whereArgs: ['$_testCedulaPrefix%'],
        );

        // Delete test clients
        await txn.delete(
          'clientes',
          where: 'cedula LIKE ?',
          whereArgs: ['$_testCedulaPrefix%'],
        );
      });
    } catch (e) {
      print('Error clearing test data: $e');
      rethrow;
    }
  }

  // Test client data
  static final List<Map<String, String>> _testClientsData = [
    {
      'nombre': 'Juan Martínez López',
      'telefono': '809-555-0101',
      'direccion': 'Calle Principal, Santo Domingo'
    },
    {
      'nombre': 'María García Rodríguez',
      'telefono': '809-555-0102',
      'direccion': 'Avenida Central, Santiago'
    },
    {
      'nombre': 'Pedro González Fernández',
      'telefono': '809-555-0103',
      'direccion': 'Calle del Comercio, La Romana'
    },
    {
      'nombre': 'Carmen Silva Domínguez',
      'telefono': '809-555-0104',
      'direccion': 'Avenida Duarte, San Fernando'
    },
    {
      'nombre': 'Antonio Pérez Sánchez',
      'telefono': '809-555-0105',
      'direccion': 'Calle Independencia, Puerto Plata'
    },
    {
      'nombre': 'Rosa Mendoza García',
      'telefono': '809-555-0106',
      'direccion': 'Avenida del Parque, Punta Cana'
    },
    {
      'nombre': 'Luis Hernández López',
      'telefono': '809-555-0107',
      'direccion': 'Calle del Mar, Sosúa'
    },
    {
      'nombre': 'Ana Díaz Torres',
      'telefono': '809-555-0108',
      'direccion': 'Avenida Principal, Cabarete'
    },
    {
      'nombre': 'Carlos Ramírez Gómez',
      'telefono': '809-555-0109',
      'direccion': 'Calle Colón, Jarabacoa'
    },
    {
      'nombre': 'Isabel Moreno Ruiz',
      'telefono': '809-555-0110',
      'direccion': 'Avenida Bolívar, Constanza'
    },
  ];

  // Test seller data
  static final List<Map<String, String>> _testSellersData = [
    {'nombre': 'Roberto Acosta', 'telefono': '809-666-0101'},
    {'nombre': 'Sofía Beltrán', 'telefono': '809-666-0102'},
    {'nombre': 'Marco Castillo', 'telefono': '809-666-0103'},
    {'nombre': 'Diana Mejía', 'telefono': '809-666-0104'},
    {'nombre': 'Felipe Navarro', 'telefono': '809-666-0105'},
    {'nombre': 'Gloria Ortega', 'telefono': '809-666-0106'},
    {'nombre': 'Héctor Parra', 'telefono': '809-666-0107'},
    {'nombre': 'Irene Quintero', 'telefono': '809-666-0108'},
    {'nombre': 'Javier Reyes', 'telefono': '809-666-0109'},
    {'nombre': 'Karina Salazar', 'telefono': '809-666-0110'},
  ];

  // Test lot data
  static final List<Map<String, dynamic>> _testLotsData = [
    {
      'block': 'A',
      'number': 1,
      'area': 180.5,
      'price': 850000.0,
    },
    {
      'block': 'A',
      'number': 2,
      'area': 200.0,
      'price': 950000.0,
    },
    {
      'block': 'B',
      'number': 5,
      'area': 175.0,
      'price': 750000.0,
    },
    {
      'block': 'B',
      'number': 6,
      'area': 190.0,
      'price': 900000.0,
    },
    {
      'block': 'C',
      'number': 10,
      'area': 220.0,
      'price': 1100000.0,
    },
    {
      'block': 'C',
      'number': 11,
      'area': 210.0,
      'price': 1050000.0,
    },
    {
      'block': 'D',
      'number': 15,
      'area': 185.0,
      'price': 925000.0,
    },
    {
      'block': 'D',
      'number': 16,
      'area': 195.0,
      'price': 975000.0,
    },
    {
      'block': 'E',
      'number': 20,
      'area': 205.0,
      'price': 1025000.0,
    },
    {
      'block': 'E',
      'number': 21,
      'area': 215.0,
      'price': 1075000.0,
    },
  ];

  // Test sale configurations with different terms
  static final List<Map<String, dynamic>> _testSalesConfigs = [
    {
      'downPaymentPercent': 5,
      'monthlyInterest': 0.5,
      'installmentCount': 12,
      'status': 'activa'
    },
    {
      'downPaymentPercent': 10,
      'monthlyInterest': 1.0,
      'installmentCount': 18,
      'status': 'activa'
    },
    {
      'downPaymentPercent': 15,
      'monthlyInterest': 1.5,
      'installmentCount': 24,
      'status': 'activa'
    },
    {
      'downPaymentPercent': 10,
      'monthlyInterest': 1.0,
      'installmentCount': 36,
      'status': 'activa'
    },
    {
      'downPaymentPercent': 20,
      'monthlyInterest': 0.75,
      'installmentCount': 12,
      'status': 'pagada'
    },
    {
      'downPaymentPercent': 10,
      'monthlyInterest': 1.25,
      'installmentCount': 48,
      'status': 'activa'
    },
    {
      'downPaymentPercent': 15,
      'monthlyInterest': 1.0,
      'installmentCount': 18,
      'status': 'activa'
    },
    {
      'downPaymentPercent': 10,
      'monthlyInterest': 0.5,
      'installmentCount': 24,
      'status': 'pagada'
    },
    {
      'downPaymentPercent': 12,
      'monthlyInterest': 1.5,
      'installmentCount': 36,
      'status': 'activa'
    },
    {
      'downPaymentPercent': 10,
      'monthlyInterest': 1.0,
      'installmentCount': 12,
      'status': 'activa'
    },
  ];

  static Future<List<int>> _insertTestClients(Transaction txn) async {
    final now = DateTime.now();
    final clientIds = <int>[];

    for (var i = 0; i < _testClientsData.length; i++) {
      final clientData = _testClientsData[i];
      final cedulaNum = (i + 1).toString().padLeft(7, '0');
      final cedula = '${_testCedulaPrefix}0000${cedulaNum}-${(i + 1) % 10}';

      final id = await txn.insert('clientes', {
        'nombre': '${_testClientPrefix}${clientData['nombre']}',
        'cedula': cedula,
        'telefono': clientData['telefono'],
        'direccion': clientData['direccion'],
        'fecha_creacion': now.toIso8601String(),
        'fecha_actualizacion': now.toIso8601String(),
      });

      clientIds.add(id);
    }

    return clientIds;
  }

  static Future<List<int>> _insertTestSellers(Transaction txn) async {
    final now = DateTime.now();
    final sellerIds = <int>[];

    for (var i = 0; i < _testSellersData.length; i++) {
      final sellerData = _testSellersData[i];
      final cedulaNum = (i + 1).toString().padLeft(7, '0');
      final cedula = '${_testCedulaPrefix}0001${cedulaNum}-${(i + 5) % 10}';

      final id = await txn.insert('vendedores', {
        'nombre': '${_testSellerPrefix}${sellerData['nombre']}',
        'cedula': cedula,
        'telefono': sellerData['telefono'],
        'fecha_creacion': now.toIso8601String(),
        'fecha_actualizacion': now.toIso8601String(),
      });

      sellerIds.add(id);
    }

    return sellerIds;
  }

  static Future<List<int>> _insertTestLots(Transaction txn) async {
    final now = DateTime.now();
    final lotIds = <int>[];

    for (var i = 0; i < _testLotsData.length; i++) {
      final lotData = _testLotsData[i];

      final id = await txn.insert('solares', {
        'manzana_numero': '${_testLotPrefix}${lotData['block']}',
        'solar_numero': lotData['number'],
        'metros_cuadrados': lotData['area'],
        'precio_por_metro': (lotData['price'] as num) / (lotData['area'] as num),
        'estado': 'disponible',
        'fecha_creacion': now.toIso8601String(),
        'fecha_actualizacion': now.toIso8601String(),
      });

      lotIds.add(id);
    }

    return lotIds;
  }

  static Future<List<int>> _insertTestSales(
    Transaction txn,
    List<int> clientIds,
    List<int> sellerIds,
    List<int> lotIds,
  ) async {
    final saleIds = <int>[];
    final now = DateTime.now();
    final defaultUserId = 1; // Default admin user

    for (var i = 0; i < clientIds.length; i++) {
      final config = _testSalesConfigs[i];
      final salePrice = _testLotsData[i]['price'];
      final downPaymentPercent = config['downPaymentPercent'];
      final monthlyInterest = config['monthlyInterest'];
      final installmentCount = config['installmentCount'];

      final requiredDownPayment =
          (salePrice * downPaymentPercent) / 100;

      final id = await txn.insert('ventas', {
        'cliente_id': clientIds[i],
        'solar_id': lotIds[i],
        'usuario_id': defaultUserId,
        'vendedor_id': sellerIds[i % sellerIds.length],
        'fecha_venta': now.toIso8601String(),
        'precio_venta': salePrice,
        'inicial_porcentaje': downPaymentPercent,
        'inicial_monto': requiredDownPayment,
        'monto_inicial_requerido': requiredDownPayment,
        'monto_inicial_pagado': requiredDownPayment, // Already paid for test
        'monto_inicial_pendiente': 0,
        'saldo_financiado': salePrice - requiredDownPayment,
        'saldo_pendiente': salePrice - requiredDownPayment,
        'interes_mensual': monthlyInterest,
        'cantidad_cuotas': installmentCount,
        'estado': config['status'],
        'monto_apartado_minimo': 0,
        'fecha_limite_inicial': now.add(Duration(days: 30)).toIso8601String(),
        'fecha_activacion': now.toIso8601String(),
        'fecha_creacion': now.toIso8601String(),
        'fecha_actualizacion': now.toIso8601String(),
      });

      saleIds.add(id);

      // Update lot status to sold
      await txn.update(
        'solares',
        {'estado': 'vendido'},
        where: 'id = ?',
        whereArgs: [lotIds[i]],
      );

      // Auto-generate installments for active sales
      if (config['status'] == 'activa') {
        await _generateInstallments(
          txn,
          id,
          salePrice - requiredDownPayment,
          monthlyInterest,
          installmentCount,
          now,
        );
      }
    }

    return saleIds;
  }

  static Future<void> _generateInstallments(
    Transaction txn,
    int saleId,
    double totalAmount,
    double monthlyInterestRate,
    int installmentCount,
    DateTime startDate,
  ) async {
    final installments = SaleCalculator.buildInstallmentSchedule(
      saleId: saleId,
      saleDate: startDate,
      financedBalance: totalAmount,
      monthlyInterest: monthlyInterestRate,
      installmentCount: installmentCount,
      createdAt: startDate,
    );

    for (final installment in installments) {
      await txn.insert('cuotas', installment.toMap()..remove('id'));
    }
  }

  static Future<void> _insertTestPayments(
    Transaction txn,
    List<int> saleIds,
  ) async {
    final now = DateTime.now();
    final paymentMethods = ['efectivo', 'cheque', 'transferencia'];

    for (var i = 0; i < saleIds.length; i++) {
      final saleId = saleIds[i];
      final paymentMethod = paymentMethods[i % paymentMethods.length];

      // Get first unpaid installment
      final installments = await txn.query(
        'cuotas',
        where: 'venta_id = ? AND estado = ?',
        whereArgs: [saleId, 'pendiente'],
        limit: 1,
      );

      if (installments.isNotEmpty) {
        final cuota = installments.first;
        final cuotaId = cuota['id'];
        final montoCuota = cuota['monto_cuota'];

        // Get client and sale info
        final sales = await txn.query(
          'ventas',
          where: 'id = ?',
          whereArgs: [saleId],
        );

        if (sales.isNotEmpty) {
          final sale = sales.first;
          final clientId = sale['cliente_id'];

          // Register partial or full payment
          await txn.insert('pagos', {
            'venta_id': saleId,
            'cliente_id': clientId,
            'cuota_id': cuotaId,
            'fecha_pago': now.subtract(Duration(days: i)).toIso8601String(),
            'monto_pagado': montoCuota,
            'metodo_pago': paymentMethod,
            'tipo_pago': 'cuota',
            'referencia': 'TEST-${saleId}-${i + 1}',
            'ano_a_pagar': now.year,
            'fecha_creacion': now.toIso8601String(),
          });
        }
      }
    }
  }
}
