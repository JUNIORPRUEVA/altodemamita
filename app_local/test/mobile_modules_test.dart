import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_solares/features/clients/domain/client.dart';
import 'package:sistema_solares/features/clients/presentation/clients_mobile.dart';
import 'package:sistema_solares/features/installments/domain/installment_detail.dart';
import 'package:sistema_solares/features/installments/presentation/installments_mobile.dart';
import 'package:sistema_solares/features/lots/domain/lot.dart';
import 'package:sistema_solares/features/lots/presentation/lots_mobile.dart';
import 'package:sistema_solares/features/payments/domain/payment_sale_option.dart';
import 'package:sistema_solares/features/payments/presentation/payments_mobile.dart';
import 'package:sistema_solares/features/sales/domain/seller.dart';
import 'package:sistema_solares/features/sales/presentation/sellers_mobile.dart';

import 'helpers/responsive_test_harness.dart';

const List<double> _widths = [320, 360, 375, 390, 412, 430];

final _now = DateTime(2026, 3, 6);

Client _client({String name = 'THELEMARQUE WISMIQUE'}) => Client(
  id: 1,
  fullName: name,
  documentId: '001-0000000-1',
  phone: '809-555-0101',
  address: 'Calle Principal 12',
  createdAt: _now,
  updatedAt: _now,
);

Lot _lot() => Lot(
  id: 1,
  blockNumber: 'M-B-1',
  lotNumber: '446',
  area: 300,
  pricePerSquareMeter: 2500,
  status: 'disponible',
  createdAt: _now,
  updatedAt: _now,
);

Seller _seller() => Seller(
  id: 1,
  name: 'Vendedor Uno',
  phone: '809-555-0202',
  documentId: '002-0000000-2',
  createdAt: _now,
  updatedAt: _now,
);

InstallmentDetail _installment({int number = 3, String status = 'pendiente'}) =>
    InstallmentDetail(
      id: number,
      installmentNumber: number,
      saleId: 10,
      clientName: 'THELEMARQUE WISMIQUE',
      clientDocumentId: '001-0000000-1',
      lotCode: 'MM-B-1-S446',
      dueDate: DateTime(2026, 6, 15),
      openingBalance: 675000,
      principalAmount: 11000,
      interestAmount: 1500,
      totalAmount: 12500,
      paidAmount: 0,
      remainingAmount: 12500,
      endingBalance: 664000,
      status: status,
    );

PaymentSaleOption _paymentSale({double pendingBalance = 631250}) =>
    PaymentSaleOption(
      saleId: 10,
      clientId: 1,
      clientName: 'THELEMARQUE WISMIQUE',
      clientDocumentId: '001-0000000-1',
      clientPhone: '809-555-0101',
      lotDisplayCode: 'MM-B-1-S446',
      pendingBalance: pendingBalance,
      requiredInitialPayment: 75000,
      paidInitialPayment: 75000,
      pendingInitialPayment: 0,
      status: 'activa',
    );

Widget _clients() => ClientsMobileView(
  clients: [_client()],
  query: '',
  isLoading: false,
  isRefreshing: false,
  refreshFailed: false,
  searchFailed: false,
  hasVisibleData: true,
  loadErrorTitle: null,
  canCreate: true,
  canUpdate: true,
  canDelete: true,
  onSearch: (_) {},
  onClearSearch: () {},
  onRetry: () {},
  onCreate: () {},
  onEdit: (_) {},
  onDelete: (_) {},
);

Widget _lots() => LotsMobileView(
  lots: [_lot()],
  query: '',
  isLoading: false,
  isRefreshing: false,
  refreshFailed: false,
  searchFailed: false,
  hasVisibleData: true,
  loadErrorTitle: null,
  canCreate: true,
  canUpdate: true,
  canDelete: true,
  onSearch: (_) {},
  onClearSearch: () {},
  onRetry: () {},
  onCreate: () {},
  onEdit: (_) {},
  onDelete: (_) {},
);

Widget _sellers() => SellersMobileView(
  sellers: [_seller()],
  query: '',
  isLoading: false,
  isRefreshing: false,
  refreshFailed: false,
  searchFailed: false,
  hasVisibleData: true,
  loadErrorTitle: null,
  canCreate: true,
  canUpdate: true,
  canDelete: true,
  onSearch: (_) {},
  onClearSearch: () {},
  onRetry: () {},
  onCreate: () {},
  onEdit: (_) {},
  onDelete: (_) {},
);

Widget _cuotas() => InstallmentsMobileView(
  installments: [_installment()],
  isLoading: false,
  totalFinanced: 675000,
  totalPaid: 12500,
  totalPending: 662500,
  hasOverdue: true,
  totalOverdueAmount: 25000,
  onSearch: (_) {},
  onClearSearch: () {},
  onRetry: () {},
);

Widget _pagos({ValueChanged<int>? onOpenSale}) => PaymentsMobileView(
  sales: [_paymentSale()],
  isLoading: false,
  isRefreshing: false,
  refreshFailed: false,
  loadErrorTitle: null,
  canCreatePayments: true,
  onSearch: (_) {},
  onClearSearch: () {},
  onRetry: () {},
  onRegisterPayment: () {},
  onOpenSale: onOpenSale ?? (_) {},
);

void main() {
  group('Listas mobile - sin desbordes', () {
    final views = <String, Widget Function()>{
      'clientes': _clients,
      'solares': _lots,
      'vendedores': _sellers,
      'cuotas': _cuotas,
      'pagos': _pagos,
    };

    for (final entry in views.entries) {
      for (final width in _widths) {
        testWidgets('${entry.key} sin desbordes a ${width.toInt()} px', (
          tester,
        ) async {
          useTestSize(tester, Size(width, 800));
          await tester.pumpWidget(testApp(entry.value()));
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key} a $width no debe desbordarse',
          );
        });
      }
    }
  });

  group('Listas mobile - estilo Ventas', () {
    testWidgets('clientes muestra nombre, documento y telefono', (
      tester,
    ) async {
      useTestSize(tester, const Size(390, 900));
      await tester.pumpWidget(testApp(_clients()));
      await tester.pumpAndSettle();

      expect(find.text('THELEMARQUE WISMIQUE'), findsOneWidget);
      expect(find.text('001-0000000-1'), findsOneWidget);
      expect(find.text('809-555-0101'), findsOneWidget);
      expect(find.byTooltip('Nuevo cliente'), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets('solares muestra codigo, area, precio y estado', (
      tester,
    ) async {
      useTestSize(tester, const Size(390, 900));
      await tester.pumpWidget(testApp(_lots()));
      await tester.pumpAndSettle();

      expect(find.text('Solar MM-B-1-S446'), findsOneWidget);
      expect(find.textContaining('300.00 m²'), findsOneWidget);
      expect(find.textContaining('RD\$750,000.00'), findsOneWidget);
      expect(find.byTooltip('Nuevo solar'), findsOneWidget);
    });

    testWidgets('vendedores muestra nombre, documento y telefono', (
      tester,
    ) async {
      useTestSize(tester, const Size(390, 900));
      await tester.pumpWidget(testApp(_sellers()));
      await tester.pumpAndSettle();

      expect(find.text('Vendedor Uno'), findsOneWidget);
      expect(find.text('002-0000000-2'), findsOneWidget);
      expect(find.byTooltip('Nuevo vendedor'), findsOneWidget);
    });

    testWidgets('cuotas muestra cuota, cliente, vence y monto', (
      tester,
    ) async {
      useTestSize(tester, const Size(390, 900));
      await tester.pumpWidget(testApp(_cuotas()));
      await tester.pumpAndSettle();

      expect(find.text('Cuota 3'), findsOneWidget);
      expect(find.text('THELEMARQUE WISMIQUE'), findsOneWidget);
      expect(find.textContaining('15/06/2026'), findsOneWidget);
      expect(find.text('Pendiente'), findsWidgets);
      expect(find.text('CUOTAS'), findsOneWidget);
    });

    testWidgets('pagos muestra cliente, solar y pendiente', (tester) async {
      useTestSize(tester, const Size(390, 900));
      await tester.pumpWidget(testApp(_pagos()));
      await tester.pumpAndSettle();

      expect(find.text('THELEMARQUE WISMIQUE'), findsOneWidget);
      expect(find.text('Solar MM-B-1-S446'), findsOneWidget);
      expect(find.text('RD\$631,250.00'), findsOneWidget);
      expect(find.byTooltip('Registrar pago'), findsOneWidget);
    });
  });

  group('Detalles mobile - pantalla completa y sin IDs tecnicos', () {
    testWidgets('detalle de cliente', (tester) async {
      useTestSize(tester, const Size(390, 900));
      await tester.pumpWidget(testApp(_clients()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('THELEMARQUE WISMIQUE'));
      await tester.pumpAndSettle();

      expect(find.text('Detalle de cliente'), findsOneWidget);
      expect(find.text('DATOS DEL CLIENTE'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.textContaining('Sync'), findsNothing);
      expect(find.textContaining('ID local'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('detalle de solar', (tester) async {
      useTestSize(tester, const Size(390, 900));
      await tester.pumpWidget(testApp(_lots()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Solar MM-B-1-S446'));
      await tester.pumpAndSettle();

      expect(find.text('Detalle de solar'), findsOneWidget);
      expect(find.text('DISPONIBLE'), findsNothing);
      expect(find.text('Disponible'), findsWidgets);
      expect(find.textContaining('RD\$750,000.00'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('detalle de vendedor', (tester) async {
      useTestSize(tester, const Size(390, 900));
      await tester.pumpWidget(testApp(_sellers()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Vendedor Uno'));
      await tester.pumpAndSettle();

      expect(find.text('Detalle de vendedor'), findsOneWidget);
      expect(find.text('DATOS DEL VENDEDOR'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('detalle de cuota', (tester) async {
      useTestSize(tester, const Size(390, 900));
      await tester.pumpWidget(testApp(_cuotas()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cuota 3'));
      await tester.pumpAndSettle();

      expect(find.text('Detalle de cuota'), findsOneWidget);
      expect(find.text('RESUMEN FINANCIERO'), findsOneWidget);
      expect(find.textContaining('RD\$12,500.00'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pagos abre el historial de la venta tocada', (tester) async {
      useTestSize(tester, const Size(390, 900));
      final opened = <int>[];
      await tester.pumpWidget(testApp(_pagos(onOpenSale: opened.add)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('THELEMARQUE WISMIQUE'));
      await tester.pumpAndSettle();

      expect(opened, [10]);
      expect(tester.takeException(), isNull);
    });
  });

  group('Estados', () {
    testWidgets('clientes usa skeleton de carga, nunca vacio', (tester) async {
      useTestSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        testApp(
          ClientsMobileView(
            clients: const [],
            query: '',
            isLoading: true,
            isRefreshing: false,
            refreshFailed: false,
            searchFailed: false,
            hasVisibleData: false,
            loadErrorTitle: null,
            canCreate: true,
            canUpdate: true,
            canDelete: true,
            onSearch: (_) {},
            onClearSearch: () {},
            onRetry: () {},
            onCreate: () {},
            onEdit: (_) {},
            onDelete: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Cargando…'), findsOneWidget);
    });

    testWidgets('clientes vacio confirmado muestra estado simple', (
      tester,
    ) async {
      useTestSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        testApp(
          ClientsMobileView(
            clients: const [],
            query: '',
            isLoading: false,
            isRefreshing: false,
            refreshFailed: false,
            searchFailed: false,
            hasVisibleData: false,
            loadErrorTitle: null,
            canCreate: true,
            canUpdate: true,
            canDelete: true,
            onSearch: (_) {},
            onClearSearch: () {},
            onRetry: () {},
            onCreate: () {},
            onEdit: (_) {},
            onDelete: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Todavía no hay clientes'), findsOneWidget);
    });
  });
}
