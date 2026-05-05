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
import 'package:sistema_solares/features/sales/presentation/sale_form_dialog.dart';

class _TestAuthProvider extends AuthProvider {
  static final DateTime _fixedNow = DateTime(2026, 5, 3);

  @override
  bool canAccess(String module, PermissionAction action) => true;

  @override
  UserModel? get currentUser => UserModel(
    id: 99,
    nombre: 'Test User',
    email: 'test@example.com',
    passwordHash: 'hash',
    passwordResetRequired: false,
    role: UserRole.admin,
    permissions: const [],
    activo: true,
    fechaCreacion: _fixedNow,
    fechaActualizacion: _fixedNow,
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late ClientRepository clientRepository;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'sale_creation_numeric_values_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    clientRepository = ClientRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  testWidgets('sale creation uses numeric values not formatted text', (
    tester,
  ) async {
    final now = DateTime(2026, 5, 3);
    SaleDraft? submittedDraft;

    await clientRepository.save(
      Client(
        fullName: 'Maria Gomez',
        documentId: '001-1234567-8',
        phone: '8095550199',
        address: 'Calle 1',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final clients = await clientRepository.fetchAll();

    await tester.binding.setSurfaceSize(const Size(1280, 860));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _TestAuthProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  submittedDraft = await SaleFormDialog.show(
                    context,
                    clients: clients,
                    availableLots: [
                      Lot(
                        id: 1,
                        blockNumber: 'A',
                        lotNumber: '10',
                        area: 180,
                        pricePerSquareMeter: 4722.2222,
                        status: 'disponible',
                        createdAt: now,
                        updatedAt: now,
                      ),
                    ],
                    sellers: const [],
                    defaults: const SaleDefaults(
                      downPaymentPercentage: 10,
                      monthlyInterest: 1,
                      installmentCount: 12,
                    ),
                    clientRepository: clientRepository,
                    lotRepository: LotRepository(appDatabase: appDatabase),
                    sellerRepository: SellerRepository(database: appDatabase),
                  );
                },
                child: const Text('Abrir venta'),
              ),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Abrir venta'));
    await _settle(tester);

    final dropdowns = tester.widgetList<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    );
    dropdowns.first.onChanged?.call(clients.single.id);
    dropdowns.last.onChanged?.call(1);
    await _settle(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Inicial real pagado'),
      '1,000.00',
    );
    await _settle(tester);

    await tester.tap(find.text('Crear venta'));
    await _settle(tester);

    expect(submittedDraft, isNotNull);
    expect(submittedDraft!.initialPaymentPaid, 1000.0);
    expect(submittedDraft!.salePrice, 850000.0);
  });
}
