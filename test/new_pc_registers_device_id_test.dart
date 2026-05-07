import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('PC nueva genera y reutiliza un device_id persistente', () async {
    final repository = SyncConfigRepository(
      preferencesFactory: SharedPreferences.getInstance,
    );

    final firstDeviceId = await repository.getOrCreateDeviceId();
    final secondDeviceId = await repository.getOrCreateDeviceId();

    expect(firstDeviceId, isNotEmpty);
    expect(firstDeviceId, hasLength(32));
    expect(secondDeviceId, firstDeviceId);
  });

  test('reset de identificacion local rota el device_id', () async {
    final repository = SyncConfigRepository(
      preferencesFactory: SharedPreferences.getInstance,
    );

    final firstDeviceId = await repository.getOrCreateDeviceId();
    final rotatedDeviceId = await repository.rotateDeviceId();
    final loadedAfterRotation = await repository.getOrCreateDeviceId();

    expect(firstDeviceId, isNotEmpty);
    expect(rotatedDeviceId, isNotEmpty);
    expect(rotatedDeviceId, isNot(firstDeviceId));
    expect(loadedAfterRotation, rotatedDeviceId);
  });
}