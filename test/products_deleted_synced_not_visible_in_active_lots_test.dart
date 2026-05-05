import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/lots/data/lot_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late LotRepository lotRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp(
      'products_deleted_not_visible_',
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

  test('products_deleted_synced_not_visible_in_active_lots_test', () async {
    final db = await appDatabase.database;
    final now = DateTime(2026, 5, 5, 13, 0).toIso8601String();

    await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-active-1',
      'version': 1,
      'manzana_numero': 'A',
      'solar_numero': '01',
      'metros_cuadrados': 100,
      'precio_por_metro': 1500,
      'estado': 'disponible',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-tombstone-1',
      'version': 2,
      'manzana_numero': 'B',
      'solar_numero': '02',
      'metros_cuadrados': 200,
      'precio_por_metro': 2500,
      'estado': 'vendido',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': now,
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    final activeLots = await lotRepository.fetchAll();
    final availableLots = await lotRepository.fetchAvailable();
    final tombstoneRows = await db.query(
      DatabaseSchema.lotsTable,
      where: 'sync_id = ?',
      whereArgs: ['lot-tombstone-1'],
      limit: 1,
    );

    expect(activeLots.map((lot) => lot.displayCode), isNot(contains('MB-S02')));
    expect(
      availableLots.map((lot) => lot.displayCode),
      isNot(contains('MB-S02')),
    );
    expect(tombstoneRows, hasLength(1));
    expect(tombstoneRows.single['deleted_at'], isNotNull);
  });
}
