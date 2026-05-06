import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('device autorizado conserva canWrite=true para operaciones offline', () async {
    final repository = SyncConfigRepository(
      preferencesFactory: SharedPreferences.getInstance,
    );

    await repository.saveDeviceWriteState(
      DeviceWriteState(
        isPrimary: true,
        canWrite: true,
        lastValidatedAt: DateTime.utc(2026, 5, 5, 23, 0, 0),
        reason: '',
      ),
    );

    final state = await repository.loadDeviceWriteState();

    expect(state.isPrimary, isTrue);
    expect(state.canWrite, isTrue);
    expect(state.reason, isEmpty);
  });
}