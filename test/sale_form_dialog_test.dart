import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/features/auth/domain/permission_model.dart';
import 'package:sistema_solares/features/auth/presentation/auth_provider.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/clients/domain/client.dart';
import 'package:sistema_solares/features/lots/data/lot_repository.dart';
import 'package:sistema_solares/features/lots/domain/lot.dart';
import 'package:sistema_solares/features/sales/domain/sale_defaults.dart';
import 'package:sistema_solares/features/sales/domain/sale_draft.dart';
import 'package:sistema_solares/features/sales/domain/seller.dart';
import 'package:sistema_solares/features/sales/presentation/sale_form_dialog.dart';
import 'package:sistema_solares/features/sales/data/seller_repository.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _configureDesktopSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Widget _buildTestApp(Widget child) {
  return ChangeNotifierProvider<AuthProvider>.value(
    value: _TestAuthProvider(),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Lot _testLot({
  required int id,
  required String blockNumber,
  required String lotNumber,
  required double area,
  required double totalPrice,
  required DateTime now,
}) {
  return Lot(
    id: id,
    blockNumber: blockNumber,
    lotNumber: lotNumber,
    area: area,
    pricePerSquareMeter: totalPrice / area,
    status: 'disponible',
    createdAt: now,
    updatedAt: now,
  );
}

class _TestAuthProvider extends AuthProvider {
  @override
  bool canAccess(String module, PermissionAction action) => true;
}

void main() {
  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late ClientRepository clientRepository;
  late LotRepository lotRepository;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'sistema_solares_sale_dialog_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    clientRepository = ClientRepository(appDatabase: appDatabase);
    lotRepository = LotRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  testWidgets(
    'muestra el formulario completo de venta sin excepciones en desktop',
    (tester) async {
      final now = DateTime(2026, 3, 26);
      final sellerRepository = SellerRepository(database: appDatabase);

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

      await sellerRepository.insert(
        Seller(
          name: 'Pedro Vendedor',
          phone: '8095550111',
          documentId: '001-7654321-0',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await _configureDesktopSurface(tester, const Size(1280, 860));

      await tester.pumpWidget(
        _buildTestApp(
          SaleFormDialog(
            clients: await clientRepository.fetchAll(),
            availableLots: [
              _testLot(
                id: 1,
                blockNumber: 'A',
                lotNumber: '10',
                area: 180,
                totalPrice: 850000,
                now: now,
              ),
            ],
            defaults: const SaleDefaults(
              downPaymentPercentage: 10,
              monthlyInterest: 1,
              installmentCount: 12,
            ),
            clientRepository: clientRepository,
            lotRepository: lotRepository,
            sellers: await sellerRepository.getAll(),
            sellerRepository: sellerRepository,
          ),
        ),
      );
      await _settle(tester);

      expect(find.text('Seleccionar cliente'), findsOneWidget);
      expect(find.text('Seleccionar vendedor'), findsOneWidget);
      expect(find.text('Seleccionar solar'), findsOneWidget);
      expect(find.text('Precio total'), findsOneWidget);
      expect(find.textContaining('Inicial minimo:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'calcula la fecha limite 25 dias despues y la limpia al completar el inicial',
    (tester) async {
      final now = DateTime(2026, 3, 26);

      await _configureDesktopSurface(tester, const Size(1280, 860));

      await tester.pumpWidget(
        _buildTestApp(
          SaleFormDialog(
            clients: const [],
            availableLots: const [],
            sellers: const [],
            defaults: const SaleDefaults(
              downPaymentPercentage: 10,
              monthlyInterest: 1,
              installmentCount: 12,
            ),
            clientRepository: clientRepository,
            lotRepository: lotRepository,
            sellerRepository: SellerRepository(database: appDatabase),
            initialDraft: SaleDraft(
              clientId: 1,
              lotId: 1,
              userId: 1,
              saleDate: now,
              salePrice: 850000,
              downPaymentPercentage: 10,
              requiredInitialPayment: 85000,
              initialPaymentPaid: 0,
              monthlyInterest: 1,
              installmentCount: 12,
            ),
          ),
        ),
      );
      await _settle(tester);

      final deadlineField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Fecha límite'),
      );
      expect(deadlineField.controller?.text, '20/04/2026');

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Inicial real pagado'),
        '85000',
      );
      await _settle(tester);

      final clearedDeadlineField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Fecha límite'),
      );
      expect(clearedDeadlineField.controller?.text, isEmpty);
    },
  );

  testWidgets(
    'agregar solar adicional desde el dialogo no lanza excepcion y actualiza el precio total',
    (tester) async {
      final now = DateTime(2026, 3, 26);
      final sellerRepository = SellerRepository(database: appDatabase);

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

      final sellerId = await sellerRepository.insert(
        Seller(
          name: 'Pedro Vendedor',
          phone: '8095550111',
          documentId: '001-7654321-0',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final clients = await clientRepository.fetchAll();
      final sellers = await sellerRepository.getAll();

      await _configureDesktopSurface(tester, const Size(1400, 1000));

      await tester.pumpWidget(
        _buildTestApp(
          SaleFormDialog(
            clients: clients,
            availableLots: [
              _testLot(
                id: 1,
                blockNumber: 'A',
                lotNumber: '10',
                area: 180,
                totalPrice: 850000,
                now: now,
              ),
              _testLot(
                id: 2,
                blockNumber: 'A',
                lotNumber: '11',
                area: 190,
                totalPrice: 900000,
                now: now,
              ),
            ],
            defaults: const SaleDefaults(
              downPaymentPercentage: 10,
              monthlyInterest: 1,
              installmentCount: 12,
            ),
            clientRepository: clientRepository,
            lotRepository: lotRepository,
            sellers: sellers,
            sellerRepository: sellerRepository,
          ),
        ),
      );
      await _settle(tester);

      final dropdowns = tester
          .widgetList<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .toList();

      dropdowns[0].onChanged?.call(clients.single.id);
      dropdowns[1].onChanged?.call(sellerId);
      dropdowns[2].onChanged?.call(1);
      await _settle(tester);

      expect(find.text('Agregar solar'), findsOneWidget);
      await tester.tap(find.text('Agregar solar'));
      await _settle(tester);

      await tester.enterText(find.byType(TextField).last, 'MA-S11');
      await _settle(tester);

      await tester.tap(find.textContaining('MA-S11').last);
      await _settle(tester);

      expect(tester.takeException(), isNull);

      final priceField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Precio total'),
      );
      expect(priceField.controller?.text, '1,750,000.00');
      expect(find.textContaining('A-S11'), findsOneWidget);
    },
  );

  testWidgets(
    'permite crear cliente rapido sin perder los datos escritos en la venta',
    (tester) async {
      final now = DateTime(2026, 3, 26);

      await _configureDesktopSurface(tester, const Size(1400, 1000));

      await tester.pumpWidget(
        _buildTestApp(
          SaleFormDialog(
            clients: const [],
            availableLots: [
              _testLot(
                id: 1,
                blockNumber: 'A',
                lotNumber: '10',
                area: 180,
                totalPrice: 850000,
                now: now,
              ),
            ],
            defaults: const SaleDefaults(
              downPaymentPercentage: 10,
              monthlyInterest: 1,
              installmentCount: 12,
            ),
            clientRepository: clientRepository,
            lotRepository: lotRepository,
            sellers: const [],
            sellerRepository: SellerRepository(database: appDatabase),
          ),
        ),
      );
      await _settle(tester);

      await tester.ensureVisible(find.text('Nuevo cliente'));
      await tester.tap(find.text('Nuevo cliente'));
      await _settle(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre').last,
        'Maria Gomez',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Cédula').last,
        '001-1234567-8',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Teléfono').last,
        '8095550199',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dirección').last,
        'Calle 1',
      );

      await tester.tap(find.text('Crear cliente'));
      await _settle(tester);

      final clients = await clientRepository.fetchAll();
      expect(clients, hasLength(1));
      expect(clients.single.fullName, 'Maria Gomez');
      expect(clients.single.documentId, '001-1234567-8');

      final clientDropdown = tester
          .widgetList<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .first;
      expect(clientDropdown.initialValue, clients.single.id);
    },
  );

  testWidgets(
    'si la cedula ya existe selecciona el cliente existente sin perder datos de la venta',
    (tester) async {
      final now = DateTime(2026, 3, 26);

      await clientRepository.save(
        Client(
          fullName: 'Cliente Existente',
          documentId: '001-1234567-8',
          phone: '8095550100',
          address: 'Direccion original',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await _configureDesktopSurface(tester, const Size(1400, 1000));

      await tester.pumpWidget(
        _buildTestApp(
          SaleFormDialog(
            clients: await clientRepository.fetchAll(),
            availableLots: [
              _testLot(
                id: 1,
                blockNumber: 'A',
                lotNumber: '10',
                area: 180,
                totalPrice: 850000,
                now: now,
              ),
            ],
            defaults: const SaleDefaults(
              downPaymentPercentage: 10,
              monthlyInterest: 1,
              installmentCount: 12,
            ),
            clientRepository: clientRepository,
            lotRepository: lotRepository,
            sellers: const [],
            sellerRepository: SellerRepository(database: appDatabase),
          ),
        ),
      );
      await _settle(tester);

      await tester.ensureVisible(find.text('Nuevo cliente'));
      await tester.tap(find.text('Nuevo cliente'));
      await _settle(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre').last,
        'Maria Gomez',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Cédula').last,
        '001-1234567-8',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Teléfono').last,
        '8095550199',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dirección').last,
        'Calle 1',
      );

      await tester.tap(find.text('Crear cliente'));
      await _settle(tester);

      final clients = await clientRepository.fetchAll();
      expect(clients, hasLength(1));
      expect(clients.single.fullName, 'Cliente Existente');
      expect(
        find.text(
          'Ya existe un cliente con esa cedula. Se selecciono el registro existente.',
        ),
        findsOneWidget,
      );

      final clientDropdown = tester
          .widgetList<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .first;
      expect(clientDropdown.initialValue, clients.single.id);
    },
  );

  testWidgets(
    'explica cuando no hay solares disponibles y mantiene acceso a nuevo cliente',
    (tester) async {
      await _configureDesktopSurface(tester, const Size(1400, 1000));

      await tester.pumpWidget(
        _buildTestApp(
          SaleFormDialog(
            clients: const [],
            availableLots: const [],
            defaults: const SaleDefaults(
              downPaymentPercentage: 10,
              monthlyInterest: 1,
              installmentCount: 12,
            ),
            clientRepository: clientRepository,
            lotRepository: lotRepository,
            sellers: const [],
            sellerRepository: SellerRepository(database: appDatabase),
          ),
        ),
      );
      await _settle(tester);

      expect(
        find.text(
          'No hay solares disponibles. Puedes crear uno desde este formulario.',
        ),
        findsOneWidget,
      );
      expect(find.text('Nuevo cliente'), findsOneWidget);
      expect(find.text('Seleccionar solar'), findsOneWidget);
      expect(find.text('Precio total'), findsOneWidget);

      await tester.tap(find.text('Nuevo cliente'));
      await _settle(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre').last,
        'Maria Gomez',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Cédula').last,
        '001-1234567-8',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Teléfono').last,
        '8095550199',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dirección').last,
        'Calle 1',
      );

      await tester.tap(find.text('Crear cliente'));
      await _settle(tester);

      final clients = await clientRepository.fetchAll();
      expect(clients, hasLength(1));
      expect(clients.single.fullName, 'Maria Gomez');
      expect(find.text('Seleccionar cliente'), findsOneWidget);
    },
  );

  testWidgets(
    'permite crear un solar desde ventas sin perder los datos escritos',
    (tester) async {
      final now = DateTime(2026, 3, 26);

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

      await _configureDesktopSurface(tester, const Size(1400, 1000));

      await tester.pumpWidget(
        _buildTestApp(
          SaleFormDialog(
            clients: await clientRepository.fetchAll(),
            availableLots: [
              _testLot(
                id: 1,
                blockNumber: 'A',
                lotNumber: '10',
                area: 180,
                totalPrice: 850000,
                now: now,
              ),
            ],
            defaults: const SaleDefaults(
              downPaymentPercentage: 10,
              monthlyInterest: 1,
              installmentCount: 12,
            ),
            clientRepository: clientRepository,
            lotRepository: lotRepository,
            sellers: const [],
            sellerRepository: SellerRepository(database: appDatabase),
          ),
        ),
      );
      await _settle(tester);

      await tester.ensureVisible(find.text('Nuevo solar'));
      await tester.tap(find.text('Nuevo solar').last);
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
        '4523.81',
      );

      await tester.tap(find.text('Crear solar'));
      await _settle(tester);

      final availableLots = await lotRepository.fetchAvailable();
      expect(availableLots, hasLength(1));
      expect(availableLots.single.displayCode, 'MB-S22');

      final lotDropdown = tester
          .widgetList<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .firstWhere(
            (widget) => widget.decoration.labelText == 'Seleccionar solar',
          );
      expect(lotDropdown.initialValue, availableLots.single.id);
    },
  );

  testWidgets(
    'permite crear un solar desde el estado sin disponibles y continuar en la venta',
    (tester) async {
      await _configureDesktopSurface(tester, const Size(1400, 1000));

      await tester.pumpWidget(
        _buildTestApp(
          SaleFormDialog(
            clients: const [],
            availableLots: const [],
            defaults: const SaleDefaults(
              downPaymentPercentage: 10,
              monthlyInterest: 1,
              installmentCount: 12,
            ),
            clientRepository: clientRepository,
            lotRepository: lotRepository,
            sellers: const [],
            sellerRepository: SellerRepository(database: appDatabase),
          ),
        ),
      );
      await _settle(tester);

      await tester.tap(find.text('Nuevo solar'));
      await _settle(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Manzana').last,
        'C',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Número').last,
        '08',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Metros cuadrados').last,
        '180',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Precio por metro').last,
        '4888.89',
      );

      await tester.tap(find.text('Crear solar'));
      await _settle(tester);

      expect(find.text('Seleccionar solar'), findsOneWidget);
      expect(find.text('Precio total'), findsOneWidget);

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
    },
  );

  testWidgets(
    'formatea el inicial real pagado con formato contable mientras se escribe',
    (tester) async {
      final now = DateTime(2026, 3, 26);

      await _configureDesktopSurface(tester, const Size(1280, 860));

      await tester.pumpWidget(
        _buildTestApp(
          SaleFormDialog(
            clients: const [],
            availableLots: [
              _testLot(
                id: 1,
                blockNumber: 'A',
                lotNumber: '10',
                area: 180,
                totalPrice: 850000,
                now: now,
              ),
            ],
            sellers: const [],
            defaults: const SaleDefaults(
              downPaymentPercentage: 10,
              monthlyInterest: 1,
              installmentCount: 12,
            ),
            clientRepository: clientRepository,
            lotRepository: lotRepository,
            sellerRepository: SellerRepository(database: appDatabase),
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
        '8590',
      );
      await _settle(tester);

      final initialField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Inicial real pagado'),
      );
      expect(initialField.controller?.text, '8,590.00');
    },
  );

  testWidgets(
    'muestra un mensaje elegante cuando el solar ya existe al crearlo desde ventas',
    (tester) async {
      final now = DateTime(2026, 3, 26);

      await lotRepository.save(
        Lot(
          blockNumber: 'B',
          lotNumber: '22',
          area: 210,
          pricePerSquareMeter: 4523.81,
          status: 'reservado',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await _configureDesktopSurface(tester, const Size(1400, 1000));

      await tester.pumpWidget(
        _buildTestApp(
          SaleFormDialog(
            clients: const [],
            availableLots: const [],
            defaults: const SaleDefaults(
              downPaymentPercentage: 10,
              monthlyInterest: 1,
              installmentCount: 12,
            ),
            clientRepository: clientRepository,
            lotRepository: lotRepository,
            sellers: const [],
            sellerRepository: SellerRepository(database: appDatabase),
          ),
        ),
      );
      await _settle(tester);

      await tester.tap(find.text('Nuevo solar'));
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
        '4523.81',
      );

      await tester.tap(find.text('Crear solar'));
      await _settle(tester);

      expect(
        find.text('Ya existe el solar MB-S22 y actualmente está reservado.'),
        findsOneWidget,
      );
    },
  );
}
