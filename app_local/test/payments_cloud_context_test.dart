import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/config/app_flags.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/network/backend_api_client.dart';
import 'package:sistema_solares/features/payments/data/payments_repository.dart';

import 'helpers/fake_backend.dart';

/// Regresión PAGOS en CLOUD_AUTHORITATIVE:
/// - El listado de ventas activas no debe truncarse a 200 (se pagina).
/// - El contexto de la venta debe venir del endpoint por-venta
///   (`/owner/sales/:saleId/payments-context`) con TODAS las cuotas y pagos,
///   prioridad vencida correcta (más antigua) e historial con nº de cuota.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'payments_cloud_context_',
    );
    appDatabase = AppDatabase.test(p.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<PaymentsRepository> buildRepository(MockClient client) async {
    final configRepository = FakeSyncConfigRepository(
      settings: buildFakeSettings(),
    );
    await configRepository.saveJwtToken('jwt-test-token');
    final apiClient = BackendApiClient(
      syncConfigRepository: configRepository,
      client: client,
    );
    return PaymentsRepository(
      appDatabase: appDatabase,
      apiClient: apiClient,
    );
  }

  test(
    'CLOUD_AUTHORITATIVE pagos pagina ventas activas mas alla de 200 (sin truncar)',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }

      final sales = List.generate(250, (index) {
        return _saleItem(id: 'sale-$index', lot: 'Mmd-S122');
      });
      final repository = await buildRepository(
        MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/owner/sales') {
            final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
            const pageSize = 200;
            final start = (page - 1) * pageSize;
            final items = start >= sales.length
                ? <Object>[]
                : sales.sublist(start, start + pageSize > sales.length ? sales.length : start + pageSize);
            return _json(200, {
              'data': {
                'items': items,
                'page': page,
                'pageSize': pageSize,
                'total': sales.length,
              },
            });
          }
          return _json(404, {'message': 'unexpected $path'});
        }),
      );

      final active = await repository.fetchActiveSales();
      expect(active, hasLength(250));
    },
  );

  test(
    'CLOUD_AUTHORITATIVE contexto de pago por venta trae cuotas completas, historial y prioridad vencida',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }

      final repository = await buildRepository(
        MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/owner/sales') {
            return _json(200, {
              'data': {
                'items': [_saleItem(id: 'sale-remote-1', lot: 'Mmd-S122')],
                'total': 1,
              },
            });
          }
          if (path == '/api/owner/sales/sale-remote-1/payments-context') {
            return _json(200, {
              'data': {
                'sale': _saleItem(id: 'sale-remote-1', lot: 'Mmd-S122'),
                'installments': _installmentsJson(),
                'payments': [
                  {
                    'id': 'payment-remote-1',
                    'syncId': 'payment-sync-1',
                    'saleId': 'sale-remote-1',
                    'installmentId': 'installment-remote-1',
                    'paidAt': '2026-09-01T10:00:00.000Z',
                    'amount': '1000',
                    'method': 'efectivo',
                    'paymentType': 'installment',
                    'reference': 'REF-1',
                    'yearToPay': 2026,
                  },
                ],
              },
            });
          }
          return _json(404, {'message': 'unexpected $path'});
        }),
      );

      final active = await repository.fetchActiveSales();
      expect(active, hasLength(1));
      final saleId = active.single.saleId;

      final context = await repository.fetchSaleContext(saleId);
      expect(context, isNotNull);
      expect(context!.installments, hasLength(4));
      // Cuotas 1 y 2 vencidas y pendientes -> prioridad = #1 (la más antigua).
      expect(context.actionableInstallment, isNotNull);
      expect(context.actionableInstallment!.installmentNumber, 1);
      expect(context.actionableInstallment!.remainingAmount, greaterThan(0));
      // La cuota 4 está futura: no es exigible.
      expect(context.installments.last.installmentNumber, 4);
      // Historial conserva el nº de cuota vinculado.
      expect(context.history, hasLength(1));
      expect(context.history.single.installmentNumber, 1);
    },
  );

  test(
    'CLOUD_AUTHORITATIVE cola de pagos trae primera pagina sin descargar todas las ventas',
    () async {
      if (cloudCutoverMode != CloudCutoverMode.cloudAuthoritative) {
        return;
      }

      var salesListCalled = false;
      final repository = await buildRepository(
        MockClient((request) async {
          final path = request.url.path;
          if (path == '/api/owner/sales') {
            salesListCalled = true;
            return _json(500, {'message': 'no debe consultar ventas globales'});
          }
          if (path == '/api/owner/payments/work-queue') {
            expect(request.url.queryParameters['page'], '1');
            expect(request.url.queryParameters['pageSize'], '100');
            return _json(200, {
              'data': {
                'items': [
                  {
                    'sale': _saleItem(id: 'sale-remote-1', lot: 'Mmd-S122'),
                    'installment': _installmentsJson().first,
                  },
                ],
                'page': 1,
                'pageSize': 100,
                'total': 12410,
                'counts': {
                  'overdue': 17,
                  'dueToday': 2,
                  'pending': 12391,
                  'partial': 1,
                },
              },
            });
          }
          return _json(404, {'message': 'unexpected $path'});
        }),
      );

      final queue = await repository.fetchWorkQueue();
      expect(queue, isNotNull);
      expect(queue!.entries, hasLength(1));
      expect(queue.total, 12410);
      expect(queue.counts.overdue, 17);
      expect(queue.entries.single.sale.clientName, 'Junior pruebas');
      expect(queue.entries.single.installment.installmentNumber, 1);
      expect(salesListCalled, isFalse);
    },
  );
}

Map<String, Object?> _saleItem({required String id, required String lot}) {
  return {
    'id': id,
    'saleId': id,
    'syncId': 'sync-$id',
    'client': 'Junior pruebas',
    'cedula': '40238377333',
    'clientPhone': '8091234567',
    'clientSyncId': 'client-sync-1',
    'lot': lot,
    'lotBlock': 'md',
    'lotNumber': '122',
    'status': 'activa',
    'saleDate': '2026-09-09T10:00:00.000Z',
    'total': '500000',
    'initialRequiredAmount': '50000',
    'initialPaid': '50000',
    'initialPendingAmount': '0',
    'reservationPaidAmount': '0',
    'financedBalance': '450000',
    'monthlyInterestRate': '1',
    'installmentCount': 12,
    'balance': '100',
    'createdAt': '2026-09-09T10:00:00.000Z',
    'updatedAt': '2026-09-09T10:00:00.000Z',
  };
}

List<Map<String, Object?>> _installmentsJson() {
  final dueDates = ['2026-08-01T00:00:00.000Z', '2026-09-01T00:00:00.000Z', '2026-10-01T00:00:00.000Z', '2026-11-01T00:00:00.000Z'];
  final paid = ['1000', '0', '0', '0'];
  final amounts = ['39981.95', '39981.95', '39981.95', '39981.95'];
  return List.generate(4, (index) {
    final number = index + 1;
    return {
      'id': 'installment-remote-$number',
      'syncId': 'installment-sync-$number',
      'saleId': 'sale-remote-1',
      'installmentNumber': number,
      'dueDate': dueDates[index],
      'openingBalance': '450000',
      'principalAmount': '35481.95',
      'interestAmount': '4500',
      'totalAmount': amounts[index],
      'paidAmount': paid[index],
      'paidPrincipalAmount': paid[index],
      'paidInterestAmount': '0',
      'endingBalance': '0',
      'status': 'pending',
      'createdAt': '2026-09-09T10:00:00.000Z',
      'updatedAt': '2026-09-09T10:00:00.000Z',
    };
  });
}

http.Response _json(int status, Object body) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}
