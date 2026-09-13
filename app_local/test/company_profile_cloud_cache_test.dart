import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/settings/data/company_repository.dart';
import 'package:sistema_solares/features/settings/domain/company_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late AppDatabase appDatabase;
  late CompanyRepository repository;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'company_profile_cloud_cache_test_',
    );
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    repository = CompanyRepository(await appDatabase.database);
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('cloud profile with data fills local cache projection', () async {
    final now = DateTime.utc(2026, 9, 13);

    await repository.cacheCloudCompanyInfo(
      CompanyInfo(
        nombre: 'Empresa Cloud',
        telefono: '8095550101',
        direccion: 'Direccion Cloud',
        logoRemoteUrl: 'https://example.test/logo.png',
        logoUploadStatus: DatabaseSchema.uploadStatusSynced,
        fechaCreacion: now,
        fechaActualizacion: now,
      ),
    );

    final cached = await repository.getCompanyInfo();

    expect(cached, isNotNull);
    expect(cached!.nombre, 'Empresa Cloud');
    expect(cached.telefono, '8095550101');
    expect(cached.direccion, 'Direccion Cloud');
    expect(cached.logoRemoteUrl, 'https://example.test/logo.png');
    expect(cached.logoUploadStatus, DatabaseSchema.uploadStatusSynced);
  });

  test('cloud empty phone and address overwrite stale local cache', () async {
    final oldDate = DateTime.utc(2026, 9, 12);
    final newDate = DateTime.utc(2026, 9, 13);

    await repository.cacheCloudCompanyInfo(
      CompanyInfo(
        nombre: 'Empresa Cache Vieja',
        telefono: '8090000000',
        direccion: 'Direccion vieja',
        fechaCreacion: oldDate,
        fechaActualizacion: oldDate,
      ),
    );

    await repository.cacheCloudCompanyInfo(
      CompanyInfo(
        nombre: 'Empresa Cloud',
        telefono: null,
        direccion: null,
        fechaCreacion: newDate,
        fechaActualizacion: newDate,
      ),
    );

    final cached = await repository.getCompanyInfo();

    expect(cached, isNotNull);
    expect(cached!.nombre, 'Empresa Cloud');
    expect(cached.telefono, isNull);
    expect(cached.direccion, isNull);
  });
}
