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
  late LotRepository lotRepository;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'sale_form_create_lot_inline_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    lotRepository = LotRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  testWidgets('sale form can create lot inline and select it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 960));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _TestAuthProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: SaleFormDialog(
              clients: const [],
              availableLots: const [],
              sellers: const [],
              defaults: const SaleDefaults(
                downPaymentPercentage: 10,
                monthlyInterest: 1,
                installmentCount: 12,
              ),
              clientRepository: ClientRepository(appDatabase: appDatabase),
              lotRepository: lotRepository,
              sellerRepository: SellerRepository(database: appDatabase),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.byKey(saleFormCreateLotButtonKey));
    await _settle(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Manzana').last,
      'B',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Número').last,
      '22',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Metros cuadrados').last,
      '210',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Precio por metro').last,
      '4500',
    );

    await tester.tap(find.text('Crear solar'));
    await _settle(tester);

    final availableLots = await lotRepository.fetchAvailable();
    expect(availableLots, hasLength(1));

    final lotDropdown = tester
        .widgetList<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>),
        )
        .firstWhere(
          (widget) => widget.decoration.labelText == 'Seleccionar solar',
        );

    expect(lotDropdown.initialValue, availableLots.single.id);
    expect(availableLots.single.displayCode, 'MB-S22');
    expect(tester.takeException(), isNull);
  });
}
