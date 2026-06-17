import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('device no autorizado conserva canWrite=false y motivo legible', () async {
    final repository = SyncConfigRepository(
      preferencesFactory: SharedPreferences.getInstance,
    );

    await repository.saveDeviceWriteState(
      DeviceWriteState(
        isPrimary: false,
        canWrite: false,
        lastValidatedAt: DateTime.utc(2026, 5, 5, 23, 0, 0),
        reason: 'Este equipo no es la PC principal autorizada para escribir.',
      ),
    );

    final state = await repository.loadDeviceWriteState();

    expect(state.isPrimary, isFalse);
    expect(state.canWrite, isFalse);
    expect(state.reason, contains('PC principal autorizada'));
  });
}