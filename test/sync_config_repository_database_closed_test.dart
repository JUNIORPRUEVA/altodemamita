import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/features/settings/data/settings_repository.dart';
import 'package:sistema_solares/models/sync/sync_runtime_state.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saveLastRun ignora database_closed durante cierre de la app', () async {
    final repository = SyncConfigRepository(
      settingsRepository: _ClosedDatabaseSettingsRepository(),
    );

    await expectLater(
      repository.saveLastRun(status: SyncRuntimeStatus.pending),
      completes,
    );
  });

  test(
    'saveLastRun propaga errores de base de datos que no son cierre',
    () async {
      final repository = SyncConfigRepository(
        settingsRepository: _UnexpectedDatabaseSettingsRepository(),
      );

      await expectLater(
        repository.saveLastRun(status: SyncRuntimeStatus.pending),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
}

class _ClosedDatabaseSettingsRepository extends SettingsRepository {
  @override
  Future<void> saveMultiple(Map<String, String> keyValues) async {
    throw _TestDatabaseException('database_closed');
  }
}

class _UnexpectedDatabaseSettingsRepository extends SettingsRepository {
  @override
  Future<void> saveMultiple(Map<String, String> keyValues) async {
    throw _TestDatabaseException('unexpected database failure');
  }
}

class _TestDatabaseException extends DatabaseException {
  _TestDatabaseException(super.message);

  @override
  Object? get result => null;

  @override
  int? getResultCode() => null;
}
