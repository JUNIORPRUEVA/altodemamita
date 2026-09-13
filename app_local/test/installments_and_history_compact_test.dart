import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sistema_solares/features/auth/domain/permission_model.dart';
import 'package:sistema_solares/features/auth/domain/user_model.dart';
import 'package:sistema_solares/features/auth/presentation/auth_provider.dart';
import 'package:sistema_solares/features/payments/data/payments_repository.dart';
import 'package:sistema_solares/features/payments/domain/payment_sale_context.dart';
import 'package:sistema_solares/features/payments/domain/payment_sale_option.dart';
import 'package:sistema_solares/features/payments/presentation/payment_history_fullscreen.dart';
import 'package:sistema_solares/features/sales/presentation/sale_detail_dialog.dart';
import 'package:sistema_solares/features/sales/presentation/widgets/installments_flat_table.dart';

import 'helpers/responsive_test_harness.dart';
import 'helpers/sale_detail_fixture.dart';

/// AuthProvider de prueba (no toca base de datos ni backend).
class _TestAuthProvider extends AuthProvider {
  _TestAuthProvider()
    : _currentUser = UserModel(
        id: 1,
        nombre: 'Administrador',
        email: 'admin@local.test',
        passwordHash: '',
        passwordResetRequired: false,
        role: UserRole.admin,
        permissions: const <PermissionModel>[],
        activo: true,
        fechaCreacion: DateTime(2026, 1, 1),
        fechaActualizacion: DateTime(2026, 1, 1),
      );

  final UserModel _currentUser;

  @override
  bool get isInitializing => false;

  @override
  bool get isAuthenticated => true;

  @override
  UserModel? get currentUser => _currentUser;

  @override
  bool canReadModule(String module) => true;

  @override
  bool canAccess(String module, PermissionAction action) => true;

  @override
  Future<void> refreshCurrentUser() async {}

  @override
  Future<void> signOut() async {}
}

class _FakePaymentsRepository extends PaymentsRepository {
  _FakePaymentsRepository({this.context, this.gate});

  final PaymentSaleContext? context;
  final Completer<void>? gate;
  int calls = 0;

  @override
  Future<PaymentSaleContext?> fetchSaleContext(int saleId) async {
    calls++;
    final pending = gate;
    if (pending != null) {
      await pending.future;
    }
    return context;
  }
}

PaymentSaleContext _paymentContext({
  double pendingBalance = 12345678.9,
  String clientName = 'CLIENTE CON NOMBRE LARGO DE PRUEBA',
}) {
  return PaymentSaleContext(
    sale: PaymentSaleOption(
      saleId: 10,
      clientId: 1,
      clientName: clientName,
      clientDocumentId: '001-0000000-1',
      clientPhone: '809-555-0101',
      lotDisplayCode: 'MM-B-1-S446',
      pendingBalance: pendingBalance,
      requiredInitialPayment: 75000,
      paidInitialPayment: 75000,
      pendingInitialPayment: 0,
      status: 'activa',
    ),
    monthlyInterest: 1,
    installments: const [],
    history: const [],
  );
}

Iterable<Scrollable> _horizontalScrollables(WidgetTester tester) {
  return tester
      .widgetList<Scrollable>(find.byType(Scrollable))
      .where(
        (scrollable) =>
            scrollable.axisDirection == AxisDirection.right ||
            scrollable.axisDirection == AxisDirection.left,
      );
}

Future<void> _pumpTable(WidgetTester tester, Size size, {int count = 24}) async {
  useTestSize(tester, size);
  await tester.pumpWidget(
    testApp(
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: 420,
            child: InstallmentsFlatTable(
              installments: installmentsFixture(count: count),
              scrollController: ScrollController(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Cuotas amortizadas (tabla plana) - compacto', () {
    for (final width in const [320.0, 360.0, 375.0, 390.0, 412.0, 430.0, 768.0]) {
      testWidgets('sin desbordes a ${width.toInt()} px', (tester) async {
        await _pumpTable(tester, Size(width, 800));

        expect(
          tester.takeException(),
          isNull,
          reason: 'ancho $width no debe desbordarse',
        );
      });
    }

    testWidgets('tiene scroll horizontal intencional', (tester) async {
      await _pumpTable(tester, const Size(320, 800), count: 120);

      // Existe un scroll horizontal real (no un overflow).
      expect(_horizontalScrollables(tester), isNotEmpty);

      final before = tester.getTopLeft(find.text('SALDO FINAL')).dx;
      await tester.drag(
        find.byType(InstallmentsFlatTable),
        const Offset(-260, 0),
      );
      await tester.pumpAndSettle();
      final after = tester.getTopLeft(find.text('SALDO FINAL')).dx;

      expect(
        after,
        lessThan(before),
        reason: 'la tabla debe desplazarse horizontalmente',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('el scroll vertical sigue funcionando', (tester) async {
      await _pumpTable(tester, const Size(320, 700), count: 120);

      final vertical = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            widget.axisDirection == AxisDirection.down,
      );
      expect(vertical, findsOneWidget);

      final before = tester.state<ScrollableState>(vertical).position.pixels;
      // Punto dentro del area visible de la tabla (el centro del ListView
      // queda fuera del viewport recortado).
      await tester.dragFrom(const Offset(140, 300), const Offset(0, -240));
      await tester.pumpAndSettle();
      final after = tester.state<ScrollableState>(vertical).position.pixels;

      expect(after, greaterThan(before));
      expect(tester.takeException(), isNull);
    });

    testWidgets('en escritorio (1024) NO usa scroll horizontal', (tester) async {
      await _pumpTable(tester, const Size(1024, 800));

      expect(_horizontalScrollables(tester), isEmpty);
      // La tabla ocupa el ancho disponible (sin ancho fijo de mobile).
      expect(
        tester.getSize(find.byType(InstallmentsFlatTable)).width,
        closeTo(1000, 1),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Ver cuotas - navegacion inmediata', () {
    testWidgets('abre la pantalla sin esperar cargas', (tester) async {
      useTestSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      openInstallmentsFullscreen(context, saleDetailFixture()),
                  child: const Text('Ver cuotas'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Ver cuotas'));
      // Sin esperar ninguna carga: la pantalla ya esta en la ruta.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Cuotas amortizadas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Ver pagos - navegacion inmediata', () {
    testWidgets('la ruta aparece ANTES de terminar la carga', (tester) async {
      useTestSize(tester, const Size(390, 844));
      final gate = Completer<void>();
      final repository = _FakePaymentsRepository(
        context: _paymentContext(),
        gate: gate,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(
              value: _TestAuthProvider(),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => openSalePaymentHistoryById(
                      context,
                      saleId: 10,
                      paymentsRepository: repository,
                    ),
                    child: const Text('Ver pagos'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Ver pagos'));
      // Un par de frames: la pantalla ya debe estar visible aunque la consulta
      // siga pendiente.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Cargando pagos…'), findsOneWidget);
      expect(repository.calls, 1);
      expect(tester.takeException(), isNull);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.textContaining('Historial de pagos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final width in const [320.0, 360.0, 375.0, 390.0, 412.0, 430.0, 768.0]) {
      testWidgets('historial de pagos sin desbordes a ${width.toInt()} px', (
        tester,
      ) async {
        useTestSize(tester, Size(width, 800));
        final repository = _FakePaymentsRepository(
          context: _paymentContext(),
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>.value(
                value: _TestAuthProvider(),
              ),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => openSalePaymentHistoryById(
                        context,
                        saleId: 10,
                        paymentsRepository: repository,
                      ),
                      child: const Text('Ver pagos'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Ver pagos'));
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'ancho $width no debe desbordarse',
        );
        // Los totales son legibles (scroll horizontal) y no se recortan.
        expect(find.textContaining('Restante por pagar'), findsOneWidget);
      });
    }

    testWidgets('error de carga es recuperable y sin detalles tecnicos', (
      tester,
    ) async {
      useTestSize(tester, const Size(390, 844));
      final repository = _FakePaymentsRepository();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(
              value: _TestAuthProvider(),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => openSalePaymentHistoryById(
                      context,
                      saleId: 10,
                      paymentsRepository: repository,
                    ),
                    child: const Text('Ver pagos'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Ver pagos'));
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos cargar los pagos de esta venta.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('http'), findsNothing);
    });
  });
}
