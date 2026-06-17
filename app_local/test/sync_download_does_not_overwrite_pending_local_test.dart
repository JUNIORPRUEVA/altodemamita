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
    tempDirectory = await Directory.systemTemp.createTemp(
      'sync_pending_local_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'sync.db'));
    await appDatabase.initialize();
    repository = ProductsSyncRepository(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('sync_download_does_not_overwrite_pending_local_test', () async {
    final db = await appDatabase.database;
    await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-sync-1',
      'id_remote': 'lot-remote-1',
      'version': 3,
      'manzana_numero': 'A',
      'solar_numero': 'LOCAL',
      'metros_cuadrados': 100,
      'precio_por_metro': 1500,
      'estado': 'reservado',
      'fecha_creacion': '2026-05-05T09:00:00.000Z',
      'fecha_actualizacion': '2026-05-05T12:00:00.000Z',
      'last_modified_local': '2026-05-05T12:00:00.000Z',
      'sync_status': DatabaseSchema.syncStatusPendingUpdate,
    });

    await repository.mergeRemoteRecords([
      {
        'id': 'lot-remote-1',
        'sync_id': 'lot-sync-1',
        'version': 2,
        'block_number': 'B',
        'lot_number': 'REMOTE',
        'area': 120,
        'price_per_square_meter': 2000,
        'status': 'vendido',
        'created_at': '2026-05-05T09:00:00.000Z',
        'updated_at': '2026-05-05T10:00:00.000Z',
        'deleted_at': null,
      },
    ]);

    final row = (await db.query(
      DatabaseSchema.lotsTable,
      where: 'sync_id = ?',
      whereArgs: ['lot-sync-1'],
      limit: 1,
    )).single;

    expect(row['solar_numero'], 'LOCAL');
    expect(row['sync_status'], DatabaseSchema.syncStatusPendingUpdate);
    expect(row['version'], 3);
  });
}
