import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_solares/features/installments/domain/installment.dart';
import 'package:sistema_solares/features/sales/domain/sale.dart';
import 'package:sistema_solares/features/sales/domain/sale_detail.dart';
import 'package:sistema_solares/features/sales/presentation/sale_detail_page.dart';

import 'helpers/responsive_test_harness.dart';

/// Fixtures locales de detalle de venta (solo presentación).
Sale _sale({
  int? id = 10,
  String? syncId = 'sync-abc-123',
  double salePrice = 750000,
  double paidInitialPayment = 75000,
  double requiredInitialPayment = 75000,
  double pendingInitialPayment = 0,
  double financedBalance = 675000,
  double pendingBalance = 631250,
  bool isFullyPaid = false,
}) {
  final date = DateTime(2026, 3, 6);
  return Sale(
    id: id,
    syncId: syncId,
    clientId: 1,
    lotId: 1,
    userId: 1,
    sellerId: 1,
    saleDate: date,
    salePrice: salePrice,
    downPaymentPercentage: 10,
    downPaymentAmount: 75000,
    requiredInitialPayment: requiredInitialPayment,
    paidInitialPayment: paidInitialPayment,
    pendingInitialPayment: pendingInitialPayment,
    financedBalance: financedBalance,
    pendingBalance: pendingBalance,
    monthlyInterest: 1,
    installmentCount: 120,
    status: 'activa',
    createdAt: date,
    updatedAt: date,
    isFullyPaid: isFullyPaid,
  );
}

Installment _installment({
  required int number,
  required double totalAmount,
  required double paidAmount,
  required String status,
}) {
  final dueDate = DateTime(2026, 3 + number, 15);
  return Installment(
    id: number,
    saleId: 10,
    installmentNumber: number,
    dueDate: dueDate,
    openingBalance: 675000,
    principalAmount: 11000,
    interestAmount: 1500,
    totalAmount: totalAmount,
    paidAmount: paidAmount,
    paidPrincipalAmount: 0,
    paidInterestAmount: 0,
    endingBalance: 664000,
    status: status,
    createdAt: dueDate,
    updatedAt: dueDate,
  );
}

SaleDetail _detail({
  Sale? sale,
  String clientName = 'THELEMARQUE WISMIQUE',
  String clientDocumentId = '001-0000000-1',
  String lotDisplayCode = 'MM-B-1-S446',
  double lotArea = 300,
  double lotPricePerSquareMeter = 2500,
  String userName = 'Administrador',
  String? sellerName = 'Vendedor Uno',
}) {
  final resolvedSale = sale ?? _sale();
  return SaleDetail(
    sale: resolvedSale,
    clientName: clientName,
    clientDocumentId: clientDocumentId,
    lotDisplayCode: lotDisplayCode,
    lotArea: lotArea,
    lotPricePerSquareMeter: lotPricePerSquareMeter,
    userName: userName,
    initialPaymentMethod: 'Efectivo',
    sellerName: sellerName,
    installments: [
      _installment(
        number: 1,
        totalAmount: 12500,
        paidAmount: 12500,
        status: 'pagada',
      ),
      _installment(
        number: 2,
        totalAmount: 12500,
        paidAmount: 0,
        status: 'pendiente',
      ),
      _installment(
        number: 3,
        totalAmount: 12500,
        paidAmount: 0,
        status: 'pendiente',
      ),
    ],
  );
}

void main() {
  group('SaleDetailPage', () {
    testWidgets('es una pagina completa con header y secciones ordenadas', (
      tester,
    ) async {
      useTestSize(tester, const Size(390, 1500));
      await tester.pumpWidget(
        testApp(SaleDetailPage(initialDetail: _detail())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Detalle de venta'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      // Aparece en la tarjeta de identidad y en la fila "Cliente".
      expect(find.text('THELEMARQUE WISMIQUE'), findsNWidgets(2));
      expect(find.text('Solar MM-B-1-S446'), findsOneWidget);
      expect(find.text('CLIENTE Y SOLAR'), findsOneWidget);
      expect(find.text('CONDICIONES DE VENTA'), findsOneWidget);
      expect(find.text('RESUMEN FINANCIERO'), findsOneWidget);
      expect(find.text('PLAN DE PAGOS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tiene los dos botones hacia cuotas y pagos', (tester) async {
      useTestSize(tester, const Size(390, 1500));
      await tester.pumpWidget(
        testApp(SaleDetailPage(initialDetail: _detail())),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, 'Ver cuotas'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Ver pagos'), findsOneWidget);
      // Progreso del plan de pagos.
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('3 cuotas'), findsOneWidget);
      expect(find.text('1 pagadas · 2 pendientes'), findsOneWidget);
    });

    testWidgets('NO muestra identificadores tecnicos', (tester) async {
      useTestSize(tester, const Size(390, 1500));
      await tester.pumpWidget(
        testApp(
          SaleDetailPage(
            initialDetail: _detail(sale: _sale(id: 10, syncId: 'sync-abc-123')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('ID local'), findsNothing);
      expect(find.textContaining('Sync ID'), findsNothing);
      expect(find.textContaining('sync_id'), findsNothing);
      expect(find.text('sync-abc-123'), findsNothing);
      expect(find.textContaining('companyId'), findsNothing);
      expect(find.textContaining('remoteId'), findsNothing);
      expect(find.textContaining('UUID'), findsNothing);
    });

    testWidgets('muestra montos completos y fecha en español', (tester) async {
      useTestSize(tester, const Size(390, 1500));
      await tester.pumpWidget(
        testApp(SaleDetailPage(initialDetail: _detail())),
      );
      await tester.pumpAndSettle();

      expect(find.text('RD\$750,000.00'), findsWidgets);
      expect(find.text('RD\$631,250.00'), findsWidgets);
      expect(find.text('06/03/2026'), findsWidgets);
      expect(find.textContaining('Mar 6'), findsNothing);
    });

    testWidgets('el menu superior ofrece imprimir, editar y eliminar', (
      tester,
    ) async {
      useTestSize(tester, const Size(390, 1500));
      await tester.pumpWidget(
        testApp(
          SaleDetailPage(
            initialDetail: _detail(),
            canUpdate: true,
            canDelete: true,
            onEdit: () async {},
            onDelete: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Imprimir documento'), findsOneWidget);
      // "Editar venta" / "Eliminar venta" existen además como acciones visibles.
      expect(find.text('Editar venta'), findsWidgets);
      expect(find.text('Eliminar venta'), findsWidgets);
    });

    testWidgets('la seccion Acciones ejecuta editar y eliminar', (
      tester,
    ) async {
      useTestSize(tester, const Size(390, 1500));
      var editTapped = 0;
      await tester.pumpWidget(
        testApp(
          SaleDetailPage(
            initialDetail: _detail(),
            canUpdate: true,
            canDelete: true,
            onEdit: () async => editTapped++,
            onDelete: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ACCIONES'), findsOneWidget);
      await tester.tap(find.text('Editar venta'));
      await tester.pumpAndSettle();
      expect(editTapped, 1);
    });

    testWidgets('estado de carga muestra progreso y vista previa', (
      tester,
    ) async {
      useTestSize(tester, const Size(390, 1500));
      final completer = Completer<SaleDetail?>();
      await tester.pumpWidget(
        testApp(
          SaleDetailPage(
            loadDetail: () => completer.future,
            previewClientName: 'THELEMARQUE WISMIQUE',
            previewLotCode: 'MM-B-1-S446',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Cargando detalle de venta…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('THELEMARQUE WISMIQUE'), findsOneWidget);
      expect(find.text('Solar MM-B-1-S446'), findsOneWidget);

      completer.complete(_detail());
      await tester.pumpAndSettle();
      expect(find.text('RESUMEN FINANCIERO'), findsOneWidget);
    });

    testWidgets('estado de error permite reintentar', (tester) async {
      useTestSize(tester, const Size(390, 1500));
      var attempts = 0;
      await tester.pumpWidget(
        testApp(
          SaleDetailPage(
            loadDetail: () async {
              attempts++;
              return attempts == 1 ? null : _detail();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos cargar el detalle de esta venta.'),
        findsOneWidget,
      );
      // Sin detalles técnicos en el error.
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('http'), findsNothing);

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(find.text('RESUMEN FINANCIERO'), findsOneWidget);
    });

    testWidgets('al eliminar con exito la pagina se cierra', (tester) async {
      useTestSize(tester, const Size(390, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SaleDetailPage(
                        initialDetail: _detail(),
                        canDelete: true,
                        onDelete: () async => true,
                      ),
                    ),
                  ),
                  child: const Text('abrir detalle'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir detalle'));
      await tester.pumpAndSettle();
      expect(find.text('Detalle de venta'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar venta'));
      await tester.pumpAndSettle();

      expect(find.text('Detalle de venta'), findsNothing);
      expect(find.text('abrir detalle'), findsOneWidget);
    });

    for (final width in const [
      320.0,
      360.0,
      375.0,
      390.0,
      412.0,
      430.0,
      600.0,
      768.0,
      834.0,
    ]) {
      testWidgets('sin desbordes a ${width.toInt()} px', (tester) async {
        useTestSize(tester, Size(width, 1600));
        await tester.pumpWidget(
          testApp(
            SaleDetailPage(
              initialDetail: _detail(
                clientName: 'CLIENTE CON UN NOMBRE EXTREMADAMENTE LARGO AQUI',
                sale: _sale(salePrice: 12345678.9, pendingBalance: 9876543.21),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'ancho $width no debe desbordarse',
        );
      });
    }
  });
}
