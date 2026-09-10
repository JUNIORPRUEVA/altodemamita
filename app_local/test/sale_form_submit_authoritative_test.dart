import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/features/auth/domain/permission_model.dart';
import 'package:sistema_solares/features/auth/domain/user_model.dart';
import 'package:sistema_solares/features/auth/presentation/auth_provider.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/clients/domain/client.dart';
import 'package:sistema_solares/features/lots/data/lot_repository.dart';
import 'package:sistema_solares/features/lots/domain/lot.dart';
import 'package:sistema_solares/features/sales/data/seller_repository.dart';
import 'package:sistema_solares/features/sales/domain/sale_defaults.dart';
import 'package:sistema_solares/features/sales/domain/sale_draft.dart';
import 'package:sistema_solares/features/sales/domain/seller.dart';
import 'package:sistema_solares/features/sales/presentation/sale_form_dialog.dart';

/// P0 CREAR VENTA: el modal SOLO se cierra cuando el handler autoritativo
/// devuelve success. Con failure permanece abierto, conserva los datos, muestra
/// el motivo y permite reintentar. El reintento con los MISMOS datos reutiliza
/// la llave idempotente; si el usuario cambia datos, genera una llave nueva.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  final now = DateTime(2026, 9, 9);

  Future<void> openDialog(
    WidgetTester tester, {
    required SaleFormSubmitHandler onSubmit,
    ValueChanged<SaleDraft?>? onResult,
  }) async {
    final clients = [
      Client(
        id: 1,
        fullName: 'Maria Gomez',
        documentId: '001-1234567-8',
        phone: '8095550199',
        createdAt: now,
        updatedAt: now,
      ),
    ];
    final sellers = <Seller>[];
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _TestAuthProvider(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    final result = await SaleFormDialog.show(
                      context,
                      clients: clients,
                      availableLots: [
                        Lot(
                          id: 1,
                          blockNumber: 'A',
                          lotNumber: '10',
                          area: 180,
                          pricePerSquareMeter: 4722.22,
                          status: 'disponible',
                          createdAt: now,
                          updatedAt: now,
                        ),
                      ],
                      sellers: sellers,
                      defaults: const SaleDefaults(
                        downPaymentPercentage: 10,
                        monthlyInterest: 1,
                        installmentCount: 12,
                      ),
                      clientRepository: ClientRepository(
                        appDatabase: appDatabase,
                      ),
                      lotRepository: LotRepository(appDatabase: appDatabase),
                      sellerRepository: SellerRepository(
                        database: appDatabase,
                      ),
                      initialDraft: SaleDraft(
                        clientId: 1,
                        lotId: 1,
                        userId: 1,
                        saleDate: now,
                        salePrice: 850000,
                        downPaymentPercentage: 10,
                        requiredInitialPayment: 85000,
                        initialPaymentPaid: 85000,
                        initialPaymentMethod: 'efectivo',
                        monthlyInterest: 1,
                        installmentCount: 12,
                        status: 'activa',
                      ),
                      dialogTitle: 'Nueva venta',
                      submitLabel: 'Crear venta',
                      onSubmit: onSubmit,
                    );
                    onResult?.call(result);
                  },
                  child: const Text('Abrir venta'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir venta'));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'sale_form_authoritative_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  testWidgets(
    'exito autoritativo: el modal se cierra y entrega el draft una sola vez',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 960));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      SaleDraft? result;
      var calls = 0;
      final opIds = <String>[];

      await openDialog(
        tester,
        onSubmit: (draft, operationId) async {
          calls += 1;
          opIds.add(operationId);
          return const SaleFormSubmitOutcome.success();
        },
        onResult: (draft) => result = draft,
      );

      expect(find.text('Nueva venta'), findsOneWidget);
      await tester.tap(find.text('Crear venta'));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(result, isNotNull);
      expect(result!.clientId, 1);
      expect(result!.lotId, 1);
      expect(find.text('Nueva venta'), findsNothing);
    },
  );

  testWidgets(
    'fallo 409 (solar ocupado): modal permanece abierto, datos intactos y '
    'mensaje visible; reintento con los mismos datos reutiliza la llave y al '
    'exito cierra',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 960));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      SaleDraft? result;
      var calls = 0;
      final opIds = <String>[];
      var failNext = true;

      await openDialog(
        tester,
        onSubmit: (draft, operationId) async {
          calls += 1;
          opIds.add(operationId);
          if (failNext) {
            return const SaleFormSubmitOutcome.failure(
              'Este solar ya tiene una venta activa. Selecciona otro solar.',
            );
          }
          return const SaleFormSubmitOutcome.success();
        },
        onResult: (draft) => result = draft,
      );

      await tester.tap(find.text('Crear venta'));
      await tester.pumpAndSettle();

      // Modal sigue abierto tras el fallo.
      expect(find.text('Nueva venta'), findsOneWidget);
      expect(find.text('No se pudo guardar la venta'), findsOneWidget);
      expect(
        find.textContaining('Este solar ya tiene una venta activa'),
        findsOneWidget,
      );

      // Los datos ingresados se conservan (precio total intacto).
      final priceField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Precio total'),
      );
      expect(priceField.controller?.text, isNotEmpty);

      // El boton vuelve a estar habilitado para reintentar.
      expect(find.text('Crear venta'), findsOneWidget);
      final submitButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Crear venta'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(submitButton.onPressed, isNotNull);

      // Reintento con los MISMOS datos -> reutiliza la llave idempotente.
      failNext = false;
      await tester.tap(find.text('Crear venta'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(opIds, hasLength(2));
      expect(opIds[1], opIds[0], reason: 'reintento identico debe reusar la llave');
      expect(find.text('Nueva venta'), findsNothing);
      expect(result, isNotNull);
    },
  );

  testWidgets(
    'si el usuario cambia datos tras un fallo, el reintento usa una llave nueva',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 960));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      var calls = 0;
      final opIds = <String>[];

      await openDialog(
        tester,
        onSubmit: (draft, operationId) async {
          calls += 1;
          opIds.add(operationId);
          if (calls == 1) {
            return const SaleFormSubmitOutcome.failure(
              'No pudimos crear la venta porque el servidor no respondió.',
            );
          }
          return const SaleFormSubmitOutcome.success();
        },
      );

      await tester.tap(find.text('Crear venta'));
      await tester.pumpAndSettle();
      expect(find.text('Nueva venta'), findsOneWidget);

      // El usuario corrige el inicial real pagado (cambia la firma del
      // payload; el precio total es de solo lectura porque deriva del solar).
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Inicial real pagado'),
        '100000',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Crear venta'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(opIds, hasLength(2));
      expect(opIds[1], isNot(opIds[0]),
          reason: 'payload distinto debe generar llave nueva');
      expect(find.text('Nueva venta'), findsNothing);
    },
  );

  testWidgets(
    'doble click mientras se envia: el handler se invoca una sola vez',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 960));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      final gate = Completer<SaleFormSubmitOutcome>();
      var calls = 0;
      SaleDraft? result;

      await openDialog(
        tester,
        onSubmit: (draft, operationId) {
          calls += 1;
          return gate.future;
        },
        onResult: (draft) => result = draft,
      );

      await tester.tap(find.text('Crear venta'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Estado "Creando..." con boton deshabilitado.
      expect(find.text('Creando…'), findsOneWidget);
      expect(calls, 1);

      // Segundo click no dispara otra llamada.
      await tester.tap(find.text('Creando…'), warnIfMissed: false);
      await tester.pump();
      expect(calls, 1);

      gate.complete(const SaleFormSubmitOutcome.success());
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(find.text('Nueva venta'), findsNothing);
    },
  );

  testWidgets(
    'fallo 500/red: modal permanece abierto sin mostrar detalles tecnicos',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 960));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      var calls = 0;

      await openDialog(
        tester,
        onSubmit: (draft, operationId) async {
          calls += 1;
          return const SaleFormSubmitOutcome.failure(
            'No pudimos crear la venta porque el servidor no respondió. '
            'Tus datos siguen en el formulario; puedes intentar nuevamente.',
          );
        },
      );

      await tester.tap(find.text('Crear venta'));
      await tester.pumpAndSettle();

      expect(find.text('Nueva venta'), findsOneWidget);
      expect(find.text('No se pudo guardar la venta'), findsOneWidget);
      // Sin stack traces ni JSON crudo en pantalla.
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('statusCode'), findsNothing);
      expect(calls, 1);
    },
  );
}

class _TestAuthProvider extends AuthProvider {
  final UserModel _testUser = UserModel(
    id: 1,
    nombre: 'Admin Test',
    email: 'admin@test.local',
    passwordHash: 'hash',
    passwordResetRequired: false,
    role: UserRole.admin,
    permissions: const [],
    activo: true,
    fechaCreacion: DateTime(2026, 1, 1),
    fechaActualizacion: DateTime(2026, 1, 1),
  );

  @override
  bool get isAuthenticated => true;

  @override
  UserModel? get currentUser => _testUser;

  @override
  bool canAccess(String module, PermissionAction action) => true;
}
