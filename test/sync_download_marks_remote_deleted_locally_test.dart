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
      'sync_remote_deleted_',
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

  test('sync_download_marks_remote_deleted_locally_test', () async {
    final db = await appDatabase.database;
    await db.insert(DatabaseSchema.lotsTable, {
      'sync_id': 'lot-sync-1',
      'id_remote': 'lot-remote-1',
      'version': 1,
      'manzana_numero': 'A',
      'solar_numero': '1',
      'metros_cuadrados': 100,
      'precio_por_metro': 1500,
      'estado': 'disponible',
      'fecha_creacion': '2026-05-05T09:00:00.000Z',
      'fecha_actualizacion': '2026-05-05T09:00:00.000Z',
      'sync_status': DatabaseSchema.syncStatusSynced,
    });

    await repository.mergeRemoteRecords([
      {
        'id': 'lot-remote-1',
        'sync_id': 'lot-sync-1',
        'version': 2,
        'updated_at': '2026-05-05T10:00:00.000Z',
        'deleted_at': '2026-05-05T10:00:00.000Z',
      },
    ]);

    final row = (await db.query(
      DatabaseSchema.lotsTable,
      where: 'sync_id = ?',
      whereArgs: ['lot-sync-1'],
      limit: 1,
    )).single;

    expect(row['deleted_at'], '2026-05-05T10:00:00.000Z');
    expect(row['sync_status'], DatabaseSchema.syncStatusSynced);
  });
}
