import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/repositories/products_sync_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late ProductsSyncRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('reconcile_products_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
    repository = ProductsSyncRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('full_reconciliation_inserts_missing_product_tombstones_test', () async {
    final db = await appDatabase.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await repository.mergeRemoteRecords([
      {
        'id': 'remote-product-10',
        'sync_id': 'product-tomb-10',
        'version': 3,
        'block_number': 'Z',
        'lot_number': '99',
        'area': 220,
        'price_per_square_meter': 1200,
        'status': 'disponible',
        'created_at': now,
        'updated_at': now,
        'deleted_at': now,
      },
    ]);

    final rows = await db.query(
      DatabaseSchema.lotsTable,
      where: 'sync_id = ?',
      whereArgs: ['product-tomb-10'],
      limit: 1,
    );
    expect(rows, isNotEmpty);
    expect((rows.first['deleted_at'] as String?)?.isNotEmpty, isTrue);
    expect(rows.first['sync_status'], DatabaseSchema.syncStatusSynced);
  });
}
