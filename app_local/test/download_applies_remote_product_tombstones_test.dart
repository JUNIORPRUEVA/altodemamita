import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/repositories/products_sync_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late ProductsSyncRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDirectory = await Directory.systemTemp.createTemp('product_tombstone_');
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

  test('inserts missing remote product tombstone locally', () async {
    final now = DateTime.now().toIso8601String();
    await repository.mergeRemoteRecords([
      {
        'id': 'remote-product-1',
        'sync_id': 'product-1',
        'version': 3,
        'block_number': 'B',
        'lot_number': '2',
        'area': 80,
        'price_per_square_meter': 900,
        'status': 'vendido',
        'created_at': now,
        'updated_at': now,
        'deleted_at': now,
      },
    ]);

    final db = await appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.lotsTable,
      where: 'sync_id = ?',
      whereArgs: ['product-1'],
      limit: 1,
    );

    expect(rows, hasLength(1));
    expect(rows.single['deleted_at'], now);
    expect(rows.single['sync_status'], DatabaseSchema.syncStatusSynced);
  });
}