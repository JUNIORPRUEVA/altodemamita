import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'device write state defaults to writable when nothing is persisted',
    () async {
      final repository = SyncConfigRepository(
        preferencesFactory: SharedPreferences.getInstance,
      );

      final state = await repository.loadDeviceWriteState();

      expect(state.canWrite, isTrue);
      expect(state.isPrimary, isFalse);
      expect(state.lastValidatedAt, isNull);
      expect(state.reason, isEmpty);
    },
  );

  test('device write state round-trips through shared preferences', () async {
    final repository = SyncConfigRepository(
      preferencesFactory: SharedPreferences.getInstance,
    );
    final now = DateTime.utc(2026, 5, 5, 20, 0, 0);

    await repository.saveDeviceWriteState(
      DeviceWriteState(
        isPrimary: false,
        canWrite: false,
        lastValidatedAt: now,
        reason: 'Este equipo no es la PC principal autorizada para escribir.',
      ),
    );

    final state = await repository.loadDeviceWriteState();

    expect(state.canWrite, isFalse);
    expect(state.isPrimary, isFalse);
    expect(state.lastValidatedAt, now);
    expect(
      state.reason,
      'Este equipo no es la PC principal autorizada para escribir.',
    );
  });
}
