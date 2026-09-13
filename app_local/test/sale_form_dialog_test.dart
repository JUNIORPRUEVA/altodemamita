import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:sistema_solares/features/sales/domain/sale_defaults.dart';
import 'package:sistema_solares/features/sales/domain/sale_draft.dart';
import 'package:sistema_solares/features/sales/domain/seller.dart';
import 'package:sistema_solares/features/sales/data/seller_repository.dart';
import 'package:sistema_solares/features/sales/presentation/sale_form_dialog.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_runtime_state.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';

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

Finder _searchableField(String label) {
  return find.widgetWithText(TextFormField, label);
}

String? _searchableFieldText(WidgetTester tester, String label) {
  return tester.widget<TextFormField>(_searchableField(label)).controller?.text;
}

/// Interacción real del nuevo selector buscable:
/// clic en el campo, escribir letras, ver sugerencias filtradas y elegir una.
Future<void> _selectSearchableOption(
  WidgetTester tester, {
  required String label,
  required String query,
  required String optionText,
}) async {
  final field = _searchableField(label);
  await tester.tap(field);
  await _settle(tester);
  await tester.enterText(field, query);
  await _settle(tester);
  expect(
    find.textContaining(optionText),
    findsWidgets,
    reason: 'El campo buscable debe mostrar sugerencias al escribir "$query".',
  );
  await tester.tap(find.text(optionText).last);
  await _settle(tester);
  FocusManager.instance.primaryFocus?.unfocus();
  await _settle(tester);
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

class _InMemoryClientRepository extends ClientRepository {
  _InMemoryClientRepository({required super.appDatabase});

  final List<Client> _clients = [];
  int _nextId = 1;

  @override
  Future<List<Client>> fetchAll({String query = ''}) async {
    return _clients.toList(growable: false);
  }

  @override
  Future<Client?> findByDocumentId(String documentId) async {
    final normalized = documentId.trim();
    for (final client in _clients) {
      if (client.documentId.trim() == normalized) {
        return client;
      }
    }
    return null;
  }

  @override
  Future<void> save(Client client) async {
    final id = client.id ?? _nextId++;
    final normalizedClient = client.copyWith(id: id);
    final index = _clients.indexWhere((existing) => existing.id == id);
    if (index == -1) {
      _clients.add(normalizedClient);
    } else {
      _clients[index] = normalizedClient;
    }
  }
}

class _InMemoryLotRepository extends LotRepository {
  _InMemoryLotRepository({required super.appDatabase});

  final List<Lot> _lots = [];
  int _nextId = 1;

  @override
  Future<List<Lot>> fetchAvailable({String query = ''}) async {
    return _lots
        .where((lot) => lot.status == 'disponible')
        .toList(growable: false);
  }

  @override
  Future<Lot?> findById(int id) async {
    for (final lot in _lots) {
      if (lot.id == id) {
        return lot;
      }
    }
    return null;
  }

  @override
  Future<void> save(Lot lot) async {
    final duplicate = _lots.where(
      (existing) =>
          existing.id != lot.id &&
          existing.blockNumber.trim().toLowerCase() ==
              lot.blockNumber.trim().toLowerCase() &&
          existing.lotNumber.trim().toLowerCase() ==
              lot.lotNumber.trim().toLowerCase(),
    );
    if (duplicate.isNotEmpty) {
      throw DuplicateLotException(duplicate.first);
    }

    final id = lot.id ?? _nextId++;
    final normalizedLot = lot.copyWith(id: id);
    final index = _lots.indexWhere((existing) => existing.id == id);
    if (index == -1) {
      _lots.add(normalizedLot);
    } else {
      _lots[index] = normalizedLot;
    }
  }
}

class _InMemorySellerRepository extends SellerRepository {
  _InMemorySellerRepository({required super.database});

  final List<Seller> _sellers = [];
  int _nextId = 1;

  @override
  Future<List<Seller>> getAll() async {
    return _sellers.toList(growable: false);
  }

  @override
  Future<List<Seller>> search(String query) async {
    final normalizedQuery = query.trim().toLowerCase();
    return _sellers
        .where(
          (seller) =>
              seller.name.toLowerCase().contains(normalizedQuery) ||
              seller.documentId.toLowerCase().contains(normalizedQuery) ||
              seller.phone.toLowerCase().contains(normalizedQuery),
        )
        .toList(growable: false);
  }

  @override
  Future<int> insert(Seller seller) async {
    final id = seller.id ?? _nextId++;
    _sellers.add(seller.copyWith(id: id));
    return id;
  }

  @override
  Future<void> update(Seller seller) async {
    final id = seller.id;
    if (id == null) {
      throw ArgumentError('Seller must have an ID to update');
    }
    final index = _sellers.indexWhere((existing) => existing.id == id);
    if (index == -1) {
      _sellers.add(seller);
    } else {
      _sellers[index] = seller;
    }
  }
}

class _FakeSyncConfigRepository extends SyncConfigRepository {
  @override
  Future<SyncSettings> loadSettings() async {
    return SyncSettings(
      baseUrl: 'https://sync.example.com',
      jwtToken: 'token',
      queueRetryInterval: const Duration(seconds: 10),
      realtimePollingInterval: const Duration(seconds: 5),
      conflictStrategy: SyncConflictStrategy.manual,
      deviceId: 'sale-form-dialog-test-device',
    );
  }

  @override
  Future<void> saveLastRun({
    String? errorMessage,
    SyncRuntimeStatus status = SyncRuntimeStatus.ok,
  }) async {}
}

void main() {
  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late SyncQueueService syncQueueService;
  late ClientRepository clientRepository;
  late LotRepository lotRepository;
  late SellerRepository sellerRepository;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'sistema_solares_sale_dialog_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    syncQueueService = SyncQueueService.test(
      appDatabase: appDatabase,
      configRepository: _FakeSyncConfigRepository(),
      conflictService: SyncConflictService(appDatabase: appDatabase),
      connectivityProbe: (_) async => false,
    );
    clientRepository = _InMemoryClientRepository(appDatabase: appDatabase);
    lotRepository = _InMemoryLotRepository(appDatabase: appDatabase);
    sellerRepository = _InMemorySellerRepository(database: appDatabase);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    syncQueueService.dispose();
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  testWidgets(
    'muestra el formulario completo de venta sin excepciones en desktop',
    (tester) async {
      final now = DateTime(2026, 3, 26);

      await _configureDesktopSurface(tester, const Size(1280, 860));

      await tester.pumpWidget(
        _buildTestApp(
          SaleFormDialog(
            clients: [
              Client(
                id: 1,
                fullName: 'Maria Gomez',
                documentId: '001-1234567-8',
                phone: '8095550199',
                address: 'Calle 1',
                createdAt: now,
                updatedAt: now,
              ),
            ],
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
            sellers: [
              Seller(
                id: 1,
                name: 'Pedro Vendedor',
                phone: '8095550111',
                documentId: '001-7654321-0',
                createdAt: now,
                updatedAt: now,
              ),
            ],
            sellerRepository: sellerRepository,
          ),
        ),
      );
      await _settle(tester);

      expect(find.text('Seleccionar cliente'), findsOneWidget);
      expect(find.text('Seleccionar vendedor'), findsOneWidget);
      expect(find.text('Seleccionar solar'), findsOneWidget);
      expect(find.text('Precio total'), findsOneWidget);
      expect(find.text('Inicial minimo requerido'), findsOneWidget);
      // El selector buscable reemplaza la lupa externa: no debe existir
      // ningún botón separado de búsqueda.
      expect(find.byTooltip('Buscar'), findsNothing);
      // Los tres selectores son campos editables de autocomplete.
      expect(_searchableField('Seleccionar cliente'), findsOneWidget);
      expect(_searchableField('Seleccionar vendedor'), findsOneWidget);
      expect(_searchableField('Seleccionar solar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('en movil usa pantalla completa y campos de una columna', (
    tester,
  ) async {
    final now = DateTime(2026, 3, 26);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      _buildTestApp(
        SaleFormDialog(
          clients: [
            Client(
              id: 1,
              fullName: 'Maria Gomez',
              documentId: '001-1234567-8',
              phone: '8095550199',
              address: 'Calle 1',
              createdAt: now,
              updatedAt: now,
            ),
          ],
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
          sellerRepository: sellerRepository,
        ),
      ),
    );
    await _settle(tester);

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Nueva venta'), findsOneWidget);
    expect(find.text('Inicial real pagado'), findsOneWidget);

    final initialPaidSize = tester.getSize(
      _searchableField('Inicial real pagado'),
    );
    expect(
      initialPaidSize.width,
      greaterThanOrEqualTo(330),
      reason: 'En movil el formulario de ventas debe ser de una columna.',
    );
    expect(tester.takeException(), isNull);
  });

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
            sellerRepository: sellerRepository,
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
      expect(deadlineField.controller?.text, '19/04/2026');

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
      final clients = [
        Client(
          id: 1,
          fullName: 'Maria Gomez',
          documentId: '001-1234567-8',
          phone: '8095550199',
          address: 'Calle 1',
          createdAt: now,
          updatedAt: now,
        ),
      ];
      final sellers = [
        Seller(
          id: 1,
          name: 'Pedro Vendedor',
          phone: '8095550111',
          documentId: '001-7654321-0',
          createdAt: now,
          updatedAt: now,
        ),
      ];

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

      await _selectSearchableOption(
        tester,
        label: 'Seleccionar cliente',
        query: 'Maria',
        optionText: 'Maria Gomez',
      );
      await _selectSearchableOption(
        tester,
        label: 'Seleccionar vendedor',
        query: 'Pedro',
        optionText: 'Pedro Vendedor',
      );
      await _selectSearchableOption(
        tester,
        label: 'Seleccionar solar',
        query: 'MA-S10',
        optionText: 'MA-S10',
      );
      await _settle(tester);

      expect(find.text('Agregar solar'), findsOneWidget);
      final addLotChip = tester.widget<ActionChip>(
        find.ancestor(
          of: find.text('Agregar solar'),
          matching: find.byType(ActionChip),
        ),
      );
      addLotChip.onPressed?.call();
      await _settle(tester);

      final addLotDialog = find.byType(AlertDialog);
      await tester.enterText(
        find.descendant(of: addLotDialog, matching: find.byType(TextField)),
        'MA-S11',
      );
      await _settle(tester);

      await tester.tap(
        find
            .descendant(
              of: addLotDialog,
              matching: find.textContaining('MA-S11'),
            )
            .last,
      );
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
            sellerRepository: sellerRepository,
          ),
        ),
      );
      await _settle(tester);

      final createClientButton = find.byKey(saleFormCreateClientButtonKey);
      expect(createClientButton, findsOneWidget);
      await tester.tap(createClientButton);
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

      // El cliente creado queda seleccionado en el campo buscable de la venta.
      expect(
        _searchableFieldText(tester, 'Seleccionar cliente'),
        'Maria Gomez',
      );
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
            sellerRepository: sellerRepository,
          ),
        ),
      );
      await _settle(tester);

      final createClientButton = find.byKey(saleFormCreateClientButtonKey);
      expect(createClientButton, findsOneWidget);
      await tester.tap(createClientButton);
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

      // Se seleccionó el registro existente en el campo buscable.
      expect(
        _searchableFieldText(tester, 'Seleccionar cliente'),
        'Cliente Existente',
      );
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
            sellerRepository: sellerRepository,
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
      expect(find.byKey(saleFormCreateClientButtonKey), findsOneWidget);
      expect(find.text('Seleccionar solar'), findsOneWidget);
      expect(find.text('Precio total'), findsOneWidget);

      await tester.tap(find.byKey(saleFormCreateClientButtonKey));
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
      final clients = [
        Client(
          id: 1,
          fullName: 'Maria Gomez',
          documentId: '001-1234567-8',
          phone: '8095550199',
          address: 'Calle 1',
          createdAt: now,
          updatedAt: now,
        ),
      ];

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
            ],
            defaults: const SaleDefaults(
              downPaymentPercentage: 10,
              monthlyInterest: 1,
              installmentCount: 12,
            ),
            clientRepository: clientRepository,
            lotRepository: lotRepository,
            sellers: const [],
            sellerRepository: sellerRepository,
          ),
        ),
      );
      await _settle(tester);

      final createLotButton = find.byKey(saleFormCreateLotButtonKey);
      expect(createLotButton, findsOneWidget);
      await tester.tap(createLotButton);
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

      // El solar creado queda seleccionado en el campo buscable de la venta.
      expect(_searchableFieldText(tester, 'Seleccionar solar'), 'MB-S22');
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
            sellerRepository: sellerRepository,
          ),
        ),
      );
      await _settle(tester);

      final createLotButton = find.byKey(saleFormCreateLotButtonKey);
      expect(createLotButton, findsOneWidget);
      await tester.tap(createLotButton);
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

      // El solar creado queda seleccionado en el campo buscable de la venta.
      expect(_searchableFieldText(tester, 'Seleccionar solar'), 'MC-S08');
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
            sellerRepository: sellerRepository,
          ),
        ),
      );
      await _settle(tester);

      await _selectSearchableOption(
        tester,
        label: 'Seleccionar solar',
        query: 'MA-S10',
        optionText: 'MA-S10',
      );
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
            sellerRepository: sellerRepository,
          ),
        ),
      );
      await _settle(tester);

      final createLotButton = find.byKey(saleFormCreateLotButtonKey);
      expect(createLotButton, findsOneWidget);
      await tester.tap(createLotButton);
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

  testWidgets('permite guardar una venta sin seleccionar vendedor', (
    tester,
  ) async {
    final now = DateTime(2026, 3, 26);
    SaleDraft? submittedDraft;
    final clients = [
      Client(
        id: 1,
        fullName: 'Maria Gomez',
        documentId: '001-1234567-8',
        phone: '8095550199',
        address: 'Calle 1',
        createdAt: now,
        updatedAt: now,
      ),
    ];

    await _configureDesktopSurface(tester, const Size(1280, 860));

    await tester.pumpWidget(
      _buildTestApp(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              submittedDraft = await SaleFormDialog.show(
                context,
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
                ],
                sellers: const [],
                defaults: const SaleDefaults(
                  downPaymentPercentage: 10,
                  monthlyInterest: 1,
                  installmentCount: 12,
                ),
                clientRepository: clientRepository,
                lotRepository: lotRepository,
                sellerRepository: sellerRepository,
              );
            },
            child: const Text('Abrir venta'),
          ),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Abrir venta'));
    await _settle(tester);

    await _selectSearchableOption(
      tester,
      label: 'Seleccionar cliente',
      query: 'Maria',
      optionText: 'Maria Gomez',
    );
    await _selectSearchableOption(
      tester,
      label: 'Seleccionar solar',
      query: 'MA-S10',
      optionText: 'MA-S10',
    );
    await _settle(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Inicial real pagado'),
      '85000',
    );
    await _settle(tester);

    await tester.tap(find.text('Crear venta'));
    await _settle(tester);

    expect(submittedDraft, isNotNull);
    expect(submittedDraft?.clientId, 1);
    expect(submittedDraft?.lotId, 1);
    expect(submittedDraft?.sellerId, isNull);
  });

  testWidgets(
    'permite crear vendedor desde ventas con cedula en cualquier formato',
    (tester) async {
      final now = DateTime(2026, 3, 26);
      final clients = [
        Client(
          id: 1,
          fullName: 'Maria Gomez',
          documentId: '001-1234567-8',
          phone: '8095550199',
          address: 'Calle 1',
          createdAt: now,
          updatedAt: now,
        ),
      ];

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
            ],
            defaults: const SaleDefaults(
              downPaymentPercentage: 10,
              monthlyInterest: 1,
              installmentCount: 12,
            ),
            clientRepository: clientRepository,
            lotRepository: lotRepository,
            sellers: const [],
            sellerRepository: sellerRepository,
          ),
        ),
      );
      await _settle(tester);

      final createSellerButton = find.byKey(saleFormCreateSellerButtonKey);
      expect(createSellerButton, findsOneWidget);
      await tester.tap(createSellerButton);
      await _settle(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre').last,
        'Pedro Lopez',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Cédula').last,
        'A-001/VENTA-77',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Teléfono').last,
        '8095550111',
      );

      await tester.tap(find.text('Crear vendedor'));
      List<Seller> sellers = const [];
      for (var attempt = 0; attempt < 20; attempt += 1) {
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        sellers = await sellerRepository.getAll();
        if (sellers.isNotEmpty) {
          break;
        }
      }

      expect(sellers, hasLength(1));
      expect(sellers.single.documentId, 'A-001/VENTA-77');

      // El vendedor creado queda seleccionado en el campo buscable.
      expect(
        _searchableFieldText(tester, 'Seleccionar vendedor'),
        'Pedro Lopez',
      );
      expect(find.text('Opcional'), findsOneWidget);
    },
  );

  testWidgets(
    'crear cliente en una venta cancelada y luego editarlo en nueva venta no lanza excepciones',
    (tester) async {
      final now = DateTime(2026, 3, 26);
      await _configureDesktopSurface(tester, const Size(1400, 1000));

      await tester.pumpWidget(
        _buildTestApp(
          Builder(
            builder: (context) {
              return FilledButton(
                onPressed: () async {
                  await SaleFormDialog.show(
                    context,
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
                    sellers: await sellerRepository.getAll(),
                    defaults: const SaleDefaults(
                      downPaymentPercentage: 10,
                      monthlyInterest: 1,
                      installmentCount: 12,
                    ),
                    clientRepository: clientRepository,
                    lotRepository: lotRepository,
                    sellerRepository: sellerRepository,
                  );
                },
                child: const Text('Abrir venta'),
              );
            },
          ),
        ),
      );
      await _settle(tester);

      await tester.tap(find.text('Abrir venta'));
      await _settle(tester);

      await tester.tap(find.byKey(saleFormCreateClientButtonKey));
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

      await tester.tap(find.text('Cancelar'));
      await _settle(tester);
      await tester.tap(find.text('Descartar cambios'));
      await _settle(tester);

      await tester.tap(find.text('Abrir venta'));
      await _settle(tester);

      await _selectSearchableOption(
        tester,
        label: 'Seleccionar cliente',
        query: 'Maria',
        optionText: 'Maria Gomez',
      );

      await tester.tap(find.byTooltip('Editar cliente'));
      await _settle(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre').last,
        'Maria Gomez Editada',
      );
      await tester.tap(find.text('Guardar cambios'));
      await _settle(tester);

      final clients = await clientRepository.fetchAll();
      expect(clients, hasLength(1));
      expect(clients.single.fullName, 'Maria Gomez Editada');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cliente: buscar por nombre filtra y seleccionar conserva el id real',
    (tester) async {
      final now = DateTime(2026, 3, 26);
      SaleDraft? submittedDraft;

      await _configureDesktopSurface(tester, const Size(1280, 860));
      await tester.pumpWidget(
        _buildTestApp(
          Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                submittedDraft = await SaleFormDialog.show(
                  context,
                  clients: [
                    Client(
                      id: 1,
                      fullName: 'Maria Gomez',
                      documentId: '001-1234567-8',
                      phone: '8095550199',
                      address: 'Calle 1',
                      createdAt: now,
                      updatedAt: now,
                    ),
                    Client(
                      id: 2,
                      fullName: 'Juan Perez',
                      documentId: '001-9999999-1',
                      phone: '8095550101',
                      address: 'Calle 2',
                      createdAt: now,
                      updatedAt: now,
                    ),
                  ],
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
                  sellerRepository: sellerRepository,
                );
              },
              child: const Text('Abrir venta'),
            ),
          ),
        ),
      );
      await _settle(tester);

      await tester.tap(find.text('Abrir venta'));
      await _settle(tester);

      // Escribir filtra: "Mar" solo deja visible a Maria Gomez.
      final clientField = _searchableField('Seleccionar cliente');
      await tester.tap(clientField);
      await tester.enterText(clientField, 'Mar');
      await _settle(tester);
      expect(find.textContaining('Maria Gomez'), findsWidgets);
      expect(find.textContaining('Juan Perez'), findsNothing);

      await tester.tap(find.text('Maria Gomez').last);
      await _settle(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(tester);
      expect(
        _searchableFieldText(tester, 'Seleccionar cliente'),
        'Maria Gomez',
      );

      // Seleccionar el solar y guardar: la venta usa el cliente real (id 1).
      await _selectSearchableOption(
        tester,
        label: 'Seleccionar solar',
        query: 'MA-S10',
        optionText: 'MA-S10',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Inicial real pagado'),
        '85000',
      );
      await _settle(tester);
      await tester.tap(find.text('Crear venta'));
      await _settle(tester);

      expect(submittedDraft, isNotNull);
      expect(submittedDraft?.clientId, 1);
      expect(submittedDraft?.lotId, 1);
      expect(submittedDraft?.sellerId, isNull);
    },
  );

  testWidgets('vendedor: escribir y seleccionar por autocomplete', (
    tester,
  ) async {
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
          sellers: [
            Seller(
              id: 1,
              name: 'Pedro Vendedor',
              phone: '8095550111',
              documentId: '001-7654321-0',
              createdAt: now,
              updatedAt: now,
            ),
            Seller(
              id: 2,
              name: 'Ana Martinez',
              phone: '8095550112',
              documentId: '001-7654321-1',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          defaults: const SaleDefaults(
            downPaymentPercentage: 10,
            monthlyInterest: 1,
            installmentCount: 12,
          ),
          clientRepository: clientRepository,
          lotRepository: lotRepository,
          sellerRepository: sellerRepository,
        ),
      ),
    );
    await _settle(tester);

    await _selectSearchableOption(
      tester,
      label: 'Seleccionar vendedor',
      query: 'Pedro',
      optionText: 'Pedro Vendedor',
    );
    expect(
      _searchableFieldText(tester, 'Seleccionar vendedor'),
      'Pedro Vendedor',
    );
    expect(find.text('Opcional'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('solar: buscar por codigo, seleccionar y actualizar el precio', (
    tester,
  ) async {
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
            _testLot(
              id: 2,
              blockNumber: 'B',
              lotNumber: '03',
              area: 200,
              totalPrice: 1000000,
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
          sellerRepository: sellerRepository,
        ),
      ),
    );
    await _settle(tester);

    await _selectSearchableOption(
      tester,
      label: 'Seleccionar solar',
      query: 'MA-S10',
      optionText: 'MA-S10',
    );
    expect(_searchableFieldText(tester, 'Seleccionar solar'), 'MA-S10');

    final priceField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Precio total'),
    );
    expect(priceField.controller?.text, '850,000.00');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editar el texto despues de seleccionar invalida la seleccion previa',
    (tester) async {
      final now = DateTime(2026, 3, 26);

      await _configureDesktopSurface(tester, const Size(1280, 860));
      await tester.pumpWidget(
        _buildTestApp(
          SaleFormDialog(
            clients: [
              Client(
                id: 1,
                fullName: 'Maria Gomez',
                documentId: '001-1234567-8',
                phone: '8095550199',
                address: 'Calle 1',
                createdAt: now,
                updatedAt: now,
              ),
            ],
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
            sellerRepository: sellerRepository,
          ),
        ),
      );
      await _settle(tester);

      await _selectSearchableOption(
        tester,
        label: 'Seleccionar cliente',
        query: 'Maria',
        optionText: 'Maria Gomez',
      );
      await _selectSearchableOption(
        tester,
        label: 'Seleccionar solar',
        query: 'MA-S10',
        optionText: 'MA-S10',
      );
      expect(find.text('Listo para registrar la venta.'), findsOneWidget);

      // Cambiar el texto sin elegir de nuevo anula la seleccion anterior.
      final clientField = _searchableField('Seleccionar cliente');
      await tester.tap(clientField);
      await tester.enterText(clientField, 'Mari');
      await _settle(tester);

      expect(find.text('Completa cliente para continuar.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'texto libre sin coincidencia no se convierte en seleccion valida',
    (tester) async {
      final now = DateTime(2026, 3, 26);

      await _configureDesktopSurface(tester, const Size(1280, 860));
      await tester.pumpWidget(
        _buildTestApp(
          SaleFormDialog(
            clients: [
              Client(
                id: 1,
                fullName: 'Maria Gomez',
                documentId: '001-1234567-8',
                phone: '8095550199',
                address: 'Calle 1',
                createdAt: now,
                updatedAt: now,
              ),
            ],
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
            sellerRepository: sellerRepository,
          ),
        ),
      );
      await _settle(tester);

      await _selectSearchableOption(
        tester,
        label: 'Seleccionar solar',
        query: 'MA-S10',
        optionText: 'MA-S10',
      );

      final clientField = _searchableField('Seleccionar cliente');
      await tester.tap(clientField);
      await tester.enterText(clientField, 'No existe este cliente');
      await _settle(tester);

      // El texto libre no cuenta como cliente valido: la venta sigue
      // incompleta y el boton crear permanece deshabilitado.
      expect(find.text('Completa cliente para continuar.'), findsOneWidget);
      final submitButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Crear venta'),
          matching: find.bySubtype<FilledButton>(),
        ),
      );
      expect(submitButton.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('teclado: flechas y Enter seleccionan y Escape cierra opciones', (
    tester,
  ) async {
    final now = DateTime(2026, 3, 26);

    await _configureDesktopSurface(tester, const Size(1280, 860));
    await tester.pumpWidget(
      _buildTestApp(
        SaleFormDialog(
          clients: [
            Client(
              id: 1,
              fullName: 'Maria Gomez',
              documentId: '001-1234567-8',
              phone: '8095550199',
              address: 'Calle 1',
              createdAt: now,
              updatedAt: now,
            ),
            Client(
              id: 2,
              fullName: 'Martin Perez',
              documentId: '001-1111111-1',
              phone: '8095550102',
              address: 'Calle 3',
              createdAt: now,
              updatedAt: now,
            ),
          ],
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
          sellerRepository: sellerRepository,
        ),
      ),
    );
    await _settle(tester);

    final clientField = _searchableField('Seleccionar cliente');
    await tester.tap(clientField);
    await _settle(tester);
    await tester.enterText(clientField, 'Mar');
    await _settle(tester);
    expect(find.text('Maria Gomez'), findsWidgets);
    expect(find.text('Martin Perez'), findsWidgets);

    // Escape cierra la lista de sugerencias sin seleccionar.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Maria Gomez'), findsNothing);
    expect(find.text('Martin Perez'), findsNothing);

    // ArrowDown resalta la segunda sugerencia y Enter (submit del campo)
    // selecciona la opción resaltada.
    await tester.enterText(clientField, 'Mar');
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _settle(tester);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);
    expect(_searchableFieldText(tester, 'Seleccionar cliente'), 'Martin Perez');
    expect(tester.takeException(), isNull);
  });
}
