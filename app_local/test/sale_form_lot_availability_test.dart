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

/// Repositorio de solares en memoria: permite simular solares vendidos y
/// conflictos de duplicado sin tocar ninguna base real.
class _InMemoryLotRepository extends LotRepository {
  _InMemoryLotRepository({required super.appDatabase, this.duplicateLot});

  final List<Lot> _lots = [];
  final Lot? duplicateLot;
  int _nextId = 100;

  void seed(List<Lot> lots) {
    _lots.addAll(lots);
  }

  @override
  Future<List<Lot>> fetchAll({String query = ''}) async {
    return _lots.toList(growable: false);
  }

  @override
  Future<List<Lot>> fetchAvailable({String query = ''}) async {
    return _lots
        .where((lot) => lot.isAvailable)
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
    final conflict = duplicateLot;
    if (conflict != null) {
      throw DuplicateLotException(conflict);
    }
    _lots.add(lot.copyWith(id: lot.id ?? _nextId++, status: 'disponible'));
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Finder _fieldByLabel(String label) {
  return find.widgetWithText(TextFormField, label);
}

Lot _lot(
  String block,
  String number, {
  required int id,
  String status = 'disponible',
}) {
  return Lot(
    id: id,
    blockNumber: block,
    lotNumber: number,
    area: 200,
    pricePerSquareMeter: 3000,
    status: status,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  late Directory tempDirectory;
  late AppDatabase appDatabase;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('sale_form_lot_av_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    required LotRepository lotRepository,
    List<Lot> availableLots = const [],
    List<Lot>? allLots,
    String? supportErrorMessage,
    Future<void> Function()? onRetrySupport,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 960));
    addTearDown(() async => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _TestAuthProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: SaleFormDialog(
              clients: const [],
              availableLots: availableLots,
              allLots: allLots,
              supportErrorMessage: supportErrorMessage,
              onRetrySupport: onRetrySupport,
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
  }

  testWidgets('un solar vendido se encuentra pero no se puede seleccionar', (
    tester,
  ) async {
    final soldLot = _lot('M-Ñ', '272', id: 1, status: 'vendido');
    final availableLot = _lot('M-N', '493', id: 2);
    final lotRepository = _InMemoryLotRepository(appDatabase: appDatabase)
      ..seed([soldLot, availableLot]);

    await pumpForm(
      tester,
      lotRepository: lotRepository,
      availableLots: [availableLot],
      allLots: [availableLot, soldLot],
    );

    final lotField = _fieldByLabel('Seleccionar solar');
    await tester.tap(lotField);
    await _settle(tester);
    await tester.enterText(lotField, '272');
    await _settle(tester);

    // Se encuentra el solar vendido y se muestra su estado.
    expect(find.text('MÑ-S272'), findsWidgets);
    expect(find.textContaining('Vendido'), findsWidgets);

    await tester.tap(find.text('MÑ-S272').last);
    await _settle(tester);

    // Aviso visible y NINGUNA selección.
    expect(
      find.text(
        'El solar MÑ-S272 ya está vendido y no puede utilizarse en otra venta.',
      ),
      findsOneWidget,
    );
    final submitButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Crear venta'),
        matching: find.bySubtype<FilledButton>(),
      ),
    );
    expect(submitButton.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un solar reservado se encuentra y explica su estado', (
    tester,
  ) async {
    final reservedLot = _lot('M-N', '494', id: 3, status: 'reservado');
    final lotRepository = _InMemoryLotRepository(appDatabase: appDatabase)
      ..seed([reservedLot]);

    await pumpForm(
      tester,
      lotRepository: lotRepository,
      availableLots: const [],
      allLots: [reservedLot],
    );

    final lotField = _fieldByLabel('Seleccionar solar');
    await tester.tap(lotField);
    await _settle(tester);
    await tester.enterText(lotField, '494');
    await _settle(tester);

    await tester.tap(find.text('MN-S494').last);
    await _settle(tester);

    expect(
      find.text(
        'El solar MN-S494 está reservado y no está disponible para una nueva venta.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('un solar disponible se puede seleccionar por numero y por codigo', (
    tester,
  ) async {
    final availableLot = _lot('M-N', '493', id: 2);
    final lotRepository = _InMemoryLotRepository(appDatabase: appDatabase)
      ..seed([availableLot]);

    await pumpForm(
      tester,
      lotRepository: lotRepository,
      availableLots: [availableLot],
      allLots: [availableLot],
    );

    final lotField = _fieldByLabel('Seleccionar solar');

    // Busqueda por numero.
    await tester.tap(lotField);
    await _settle(tester);
    await tester.enterText(lotField, '493');
    await _settle(tester);
    expect(find.text('MN-S493'), findsWidgets);

    // Busqueda por codigo completo.
    await tester.enterText(lotField, 'M-N-S493');
    await _settle(tester);
    expect(find.text('MN-S493'), findsWidgets);

    await tester.tap(find.text('MN-S493').last);
    await _settle(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await _settle(tester);

    expect(find.text('Completa cliente para continuar.'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(_fieldByLabel('Seleccionar solar'))
          .controller
          ?.text,
      'MN-S493',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('crear un solar duplicado muestra el motivo y no selecciona nada', (
    tester,
  ) async {
    final soldLot = _lot('M-Ñ', '272', id: 1, status: 'vendido');
    final lotRepository = _InMemoryLotRepository(
      appDatabase: appDatabase,
      duplicateLot: soldLot,
    )..seed([soldLot]);

    await pumpForm(
      tester,
      lotRepository: lotRepository,
      availableLots: const [],
      allLots: [soldLot],
    );

    await tester.tap(find.byKey(saleFormCreateLotButtonKey));
    await _settle(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Manzana').last,
      'Ñ',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Número').last,
      '272',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Metros cuadrados').last,
      '200',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Precio por metro').last,
      '3000',
    );

    await tester.tap(find.text('Crear solar'));
    await _settle(tester);

    expect(
      find.text(
        'El solar MÑ-S272 ya está vendido y no puede utilizarse en otra venta.',
      ),
      findsOneWidget,
      reason: 'El conflicto de duplicado debe ser visible para el operador.',
    );

    // El formulario sigue abierto y el solar NO quedó seleccionado.
    expect(find.text('Crear venta'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(_fieldByLabel('Seleccionar solar'))
          .controller
          ?.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('un fallo de carga de solares no se presenta como lista vacia', (
    tester,
  ) async {
    final availableLot = _lot('M-N', '493', id: 2);
    final lotRepository = _InMemoryLotRepository(appDatabase: appDatabase)
      ..seed([availableLot]);

    var retried = false;
    await pumpForm(
      tester,
      lotRepository: lotRepository,
      availableLots: const [],
      allLots: const [],
      supportErrorMessage:
          'No pudimos actualizar los solares. Intenta nuevamente.',
      onRetrySupport: () async {
        retried = true;
      },
    );

    expect(
      find.text('No pudimos actualizar los solares. Intenta nuevamente.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Reintentar carga de solares'));
    await _settle(tester);

    expect(retried, isTrue);
    // Tras reintentar se recarga la lista real de solares.
    expect(find.text('No pudimos actualizar los solares. Intenta nuevamente.'),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
}
