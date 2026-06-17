import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/features/auth/domain/permission_model.dart';
import 'package:sistema_solares/features/auth/presentation/auth_provider.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/lots/data/lot_repository.dart';
import 'package:sistema_solares/features/lots/domain/lot.dart';
import 'package:sistema_solares/features/sales/data/seller_repository.dart';
import 'package:sistema_solares/features/sales/domain/sale_defaults.dart';
import 'package:sistema_solares/features/sales/presentation/sale_form_dialog.dart';

class _TestAuthProvider extends AuthProvider {
  @override
  bool canAccess(String module, PermissionAction action) => true;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  late Directory tempDirectory;
  late AppDatabase appDatabase;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'sale_form_formatted_amounts_',
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

  testWidgets('sale form uses formatted RD amounts', (tester) async {
    final now = DateTime(2026, 5, 3);

    await tester.binding.setSurfaceSize(const Size(1280, 860));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _TestAuthProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: SaleFormDialog(
              clients: const [],
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
              clientRepository: ClientRepository(appDatabase: appDatabase),
              lotRepository: LotRepository(appDatabase: appDatabase),
              sellerRepository: SellerRepository(database: appDatabase),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);

    final lotDropdown = tester
        .widgetList<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>),
        )
        .firstWhere(
          (widget) => widget.decoration.labelText == 'Seleccionar solar',
        );
    lotDropdown.onChanged?.call(1);
    await _settle(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Inicial real pagado'),
      '625000',
    );
    await _settle(tester);

    final initialPaidField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Inicial real pagado'),
    );
    expect(initialPaidField.controller?.text, '625,000.00');

    final requiredInitialField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Inicial minimo requerido'),
    );
    expect(requiredInitialField.initialValue, '85,000.00');

    final priceField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Precio total'),
    );
    expect(priceField.controller?.text, '850,000.00');
  });
}
