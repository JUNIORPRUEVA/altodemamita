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

DropdownButtonFormField<int> _dropdownByLabel(
  WidgetTester tester,
  String label,
) {
  return tester
      .widgetList<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>),
      )
      .firstWhere((widget) => widget.decoration.labelText == label);
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

      final dropdowns = tester
          .widgetList<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .toList();

      dropdowns[0].onChanged?.call(clients.single.id);
      dropdowns[1].onChanged?.call(sellers.single.id);
      dropdowns[2].onChanged?.call(1);
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
            sellerRepository: sellerRepository,
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

    _dropdownByLabel(tester, 'Seleccionar cliente').onChanged?.call(1);
    _dropdownByLabel(tester, 'Seleccionar solar').onChanged?.call(1);
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

      final sellerDropdown = _dropdownByLabel(tester, 'Seleccionar vendedor');
      expect(sellerDropdown.initialValue, sellers.single.id);
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

      await tester.tap(find.byTooltip('Buscar').first);
      await _settle(tester);

      await tester.enterText(find.byType(TextField).last, 'Maria');
      await _settle(tester);

      await tester.tap(find.textContaining('Maria Gomez').last);
      await _settle(tester);

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
}
