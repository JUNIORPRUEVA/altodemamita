import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares_owner/core/models/owner_snapshot.dart';
import 'package:sistema_solares_owner/core/services/api_client.dart';
import 'package:sistema_solares_owner/core/services/customer_session_store.dart';
import 'package:sistema_solares_owner/core/services/owner_snapshot_cache.dart';

/// Device-level isolation contract: a cached customer snapshot and the stored
/// session must be removable so a different customer signing in on the same
/// device can never see the previous customer's business data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory supportDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('owner_cache_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return supportDir.path;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (supportDir.existsSync()) {
      supportDir.deleteSync(recursive: true);
    }
  });

  test('owner snapshot cache can be written, read and cleared', () async {
    const cache = OwnerSnapshotCache();
    const snapshot = OwnerSnapshot(
      dashboard: {'scope': 'authenticated-customer'},
      clients: [
        {'syncId': 'client-a', 'name': 'Cliente A'},
      ],
      sellers: [],
      lots: [],
      sales: [],
      installments: [],
      payments: [],
    );

    await cache.write(snapshot);
    final restored = await cache.read();
    expect(restored, isNotNull);
    expect(restored!.clients.single['name'], 'Cliente A');

    await cache.clear();
    expect(await cache.read(), isNull);
  });

  test('logout clearing removes session and cached snapshot files', () async {
    const sessionStore = CustomerSessionStore();
    const cache = OwnerSnapshotCache();

    await sessionStore.write(
      const AuthSession(
        accessToken: 'jwt-customer-a',
        userName: 'Cliente A',
        email: 'cliente.a@example.test',
      ),
    );
    await cache.write(
      const OwnerSnapshot(
        dashboard: {'scope': 'authenticated-customer'},
        clients: [
          {'syncId': 'client-a'},
        ],
        sellers: [],
        lots: [],
        sales: [],
        installments: [],
        payments: [],
      ),
    );

    expect(
      File('${supportDir.path}${Platform.pathSeparator}customer_session.json')
          .existsSync(),
      isTrue,
    );
    expect(
      File(
        '${supportDir.path}${Platform.pathSeparator}customer_snapshot_cache.json',
      ).existsSync(),
      isTrue,
    );

    await sessionStore.clear();
    await cache.clear();

    expect(await sessionStore.read(), isNull);
    expect(await cache.read(), isNull);
    expect(supportDir.listSync(), isEmpty);
  });
}
