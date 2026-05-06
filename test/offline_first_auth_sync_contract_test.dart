import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/features/auth/data/auth_service.dart';
import 'package:sistema_solares/features/clients/data/client_repository.dart';
import 'package:sistema_solares/features/clients/domain/client.dart';
import 'package:sistema_solares/features/payments/data/payments_repository.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/models/sync/sync_status.dart';
import 'package:sistema_solares/repositories/users_sync_repository.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';
import 'package:sistema_solares/services/sync/sync_conflict_service.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';

import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('offline-first auth/sync contract', () {
    late Directory tempDirectory;
    late AppDatabase appDatabase;
    late FakeBackendState backendState;
    late FakeSyncConfigRepository configRepository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDirectory = await Directory.systemTemp.createTemp(
        'offline_first_auth_sync_contract_',
      );
      appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
      await appDatabase.initialize();
      backendState = FakeBackendState()
        ..initialized = true
        ..adminEmail = 'admin@gmail.com'
        ..adminPassword = 'Ayleen10'
        ..adminFullName = 'Admin Remoto';
      configRepository = FakeSyncConfigRepository(
        settings: buildFakeSettings(),
      );
    });

    tearDown(() async {
      await appDatabase.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('new_pc_without_internet_requires_first_connection_test', () async {
      backendState.offline = true;
      final authService = AuthService(
        appDatabase: appDatabase,
        syncConfigRepository: configRepository,
        httpClient: FakeBackendHttpClient(state: backendState),
      );

      await expectLater(
        authService.signInHybrid(
          email: 'admin@gmail.com',
          password: 'Ayleen10',
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            AuthService.firstConnectionRequiredMessage,
          ),
        ),
      );
    });

    test(
      'new_pc_with_internet_downloads_user_and_caches_locally_test',
      () async {
        final authService = AuthService(
          appDatabase: appDatabase,
          syncConfigRepository: configRepository,
          httpClient: FakeBackendHttpClient(state: backendState),
        );

        final result = await authService.signInHybrid(
          email: 'Admin@gmail.com',
          password: 'Ayleen10',
        );

        expect(result.mode, AuthSignInMode.online);
        final db = await appDatabase.database;
        final rows = await db.query(
          DatabaseSchema.usersTable,
          columns: ['email', 'id_remote', 'remote_auth_id', 'password_hash'],
          where: 'LOWER(email)=?',
          whereArgs: ['admin@gmail.com'],
          limit: 1,
        );
        expect(rows, hasLength(1));
        expect(rows.first['id_remote'], isNotNull);
        expect(rows.first['remote_auth_id'], isNotNull);
        expect((rows.first['password_hash'] as String).trim(), isNotEmpty);
      },
    );

    test('online_login_updates_local_user_hash_and_permissions_test', () async {
      final authService = AuthService(
        appDatabase: appDatabase,
        syncConfigRepository: configRepository,
        httpClient: FakeBackendHttpClient(state: backendState),
      );

      await authService.signInHybrid(
        email: 'admin@gmail.com',
        password: 'Ayleen10',
      );
      final db = await appDatabase.database;
      final first = (await db.query(
        DatabaseSchema.usersTable,
        columns: ['id', 'password_hash'],
        where: 'LOWER(email)=?',
        whereArgs: ['admin@gmail.com'],
        limit: 1,
      )).single;
      final userId = first['id'] as int;
      final firstHash = first['password_hash'] as String;

      backendState.adminPassword = 'NuevaClave2026';
      await authService.signInHybrid(
        email: 'admin@gmail.com',
        password: 'NuevaClave2026',
      );

      final second = (await db.query(
        DatabaseSchema.usersTable,
        columns: ['password_hash'],
        where: 'id = ?',
        whereArgs: [userId],
        limit: 1,
      )).single;
      final permissionRows = await db.query(
        DatabaseSchema.permissionsTable,
        columns: ['id'],
        where: 'usuario_id = ?',
        whereArgs: [userId],
      );

      expect((second['password_hash'] as String).trim(), isNotEmpty);
      expect(second['password_hash'], isNot(firstHash));
      expect(permissionRows, isNotEmpty);
    });

    test('offline_login_with_cached_user_works_test', () async {
      final authService = AuthService(
        appDatabase: appDatabase,
        syncConfigRepository: configRepository,
        httpClient: FakeBackendHttpClient(state: backendState),
      );

      await authService.signInHybrid(
        email: 'admin@gmail.com',
        password: 'Ayleen10',
      );
      await authService.signOut();
      backendState.offline = true;

      final result = await authService.signInHybrid(
        email: 'admin@gmail.com',
        password: 'Ayleen10',
      );

      expect(result.mode, AuthSignInMode.offline);
      expect(result.user.email, 'admin@gmail.com');
    });

    test('backend_timeout_falls_back_to_local_login_test', () async {
      final onlineAuth = AuthService(
        appDatabase: appDatabase,
        syncConfigRepository: configRepository,
        httpClient: FakeBackendHttpClient(state: backendState),
      );
      await onlineAuth.signInHybrid(
        email: 'admin@gmail.com',
        password: 'Ayleen10',
      );
      await onlineAuth.signOut();

      final timeoutAuth = AuthService(
        appDatabase: appDatabase,
        syncConfigRepository: configRepository,
        httpClient: _TimeoutOnLoginHttpClient(backendState),
      );

      final result = await timeoutAuth.signInHybrid(
        email: 'admin@gmail.com',
        password: 'Ayleen10',
      );

      expect(result.mode, AuthSignInMode.offline);
      expect(result.user.email, 'admin@gmail.com');
    });

    test(
      'backend_invalid_credentials_does_not_use_local_fallback_test',
      () async {
        final authService = AuthService(
          appDatabase: appDatabase,
          syncConfigRepository: configRepository,
          httpClient: FakeBackendHttpClient(state: backendState),
        );
        await authService.signInHybrid(
          email: 'admin@gmail.com',
          password: 'Ayleen10',
        );
        await authService.signOut();

        backendState.adminPassword = 'clave-remota-diferente';

        await expectLater(
          authService.signInHybrid(
            email: 'admin@gmail.com',
            password: 'Ayleen10',
          ),
          throwsA(
            isA<AuthException>().having(
              (e) => e.message,
              'message',
              AuthService.invalidLocalCredentialsMessage,
            ),
          ),
        );
      },
    );

    test('user_sync_dedup_by_email_and_remote_id_test', () async {
      final repository = UsersSyncRepository(appDatabase: appDatabase);
      final db = await appDatabase.database;
      final now = DateTime.now().toIso8601String();

      await db.insert(DatabaseSchema.usersTable, {
        'sync_id': 'local-user-sync-1',
        'id_remote': null,
        'remote_auth_id': null,
        'nombre': 'Local User',
        'email': 'admin@gmail.com',
        'password_hash': 'local-hash',
        'password_reset_required': 0,
        'rol': 'admin',
        'activo': 1,
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'sync_status': DatabaseSchema.syncStatusPendingCreate,
      });

      await repository.mergeRemoteRecords([
        {
          'id': 'remote-admin-1',
          'sync_id': 'remote-sync-1',
          'version': 2,
          'full_name': 'Remote Admin',
          'email': 'admin@gmail.com',
          'password_hash': null,
          'password_reset_required': false,
          'role': 'admin',
          'is_active': true,
          'created_at': now,
          'updated_at': now,
          'deleted_at': null,
        },
      ]);

      final rows = await db.query(
        DatabaseSchema.usersTable,
        columns: ['id', 'sync_id', 'id_remote', 'remote_auth_id'],
        where: 'LOWER(email)=?',
        whereArgs: ['admin@gmail.com'],
      );

      expect(rows, hasLength(1));
      expect(rows.first['sync_id'], 'remote-sync-1');
      expect(rows.first['id_remote'], 'remote-admin-1');
      expect(rows.first['remote_auth_id'], 'remote-admin-1');
    });

    test('remote_sync_never_clears_local_password_hash_test', () async {
      final repository = UsersSyncRepository(appDatabase: appDatabase);
      final db = await appDatabase.database;
      final now = DateTime.now().toIso8601String();
      const localHash = 'hash-local-no-borrar';

      await db.insert(DatabaseSchema.usersTable, {
        'sync_id': 'user-sync-keep-hash',
        'id_remote': 'remote-admin-1',
        'remote_auth_id': 'remote-admin-1',
        'nombre': 'Admin Local',
        'email': 'admin@gmail.com',
        'password_hash': localHash,
        'password_reset_required': 0,
        'rol': 'admin',
        'activo': 1,
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'sync_status': DatabaseSchema.syncStatusPendingUpdate,
      });

      await repository.mergeRemoteRecords([
        {
          'id': 'remote-admin-1',
          'sync_id': 'user-sync-keep-hash',
          'version': 2,
          'full_name': 'Admin Nube',
          'email': 'admin@gmail.com',
          'password_hash': '',
          'password_reset_required': false,
          'role': 'admin',
          'is_active': true,
          'created_at': now,
          'updated_at': now,
          'deleted_at': null,
        },
      ]);

      final row = (await db.query(
        DatabaseSchema.usersTable,
        columns: ['password_hash'],
        where: 'LOWER(email)=?',
        whereArgs: ['admin@gmail.com'],
        limit: 1,
      )).single;

      expect(row['password_hash'], localHash);
    });

    test('offline_crud_creates_sync_queue_entries_test', () async {
      final apiClient = _MemorySyncApiClient();
      final queue = SyncQueueService.test(
        appDatabase: appDatabase,
        configRepository: configRepository,
        apiClient: apiClient,
        conflictService: SyncConflictService(appDatabase: appDatabase),
        connectivityProbe: (_) async => false,
      );
      addTearDown(queue.dispose);
      final clients = ClientRepository(
        appDatabase: appDatabase,
        syncQueueService: queue,
      );
      queue.registerRepository(clients);

      final now = DateTime.now();
      await clients.save(
        Client(
          fullName: 'Cliente Offline Uno',
          documentId: '001-0001111-1',
          createdAt: now,
          updatedAt: now,
          syncStatus: SyncStatus.pending,
        ),
      );

      await queue.refreshScope('clients');
      final db = await appDatabase.database;
      final queueRows = await db.query(DatabaseSchema.syncQueueTable);

      expect(queueRows, isNotEmpty);
      expect(queueRows.first['scope'], 'clients');
    });

    test(
      'reconnect_syncs_pending_operations_without_duplicates_test',
      () async {
        var online = false;
        final apiClient = _MemorySyncApiClient();
        final queue = SyncQueueService.test(
          appDatabase: appDatabase,
          configRepository: configRepository,
          apiClient: apiClient,
          conflictService: SyncConflictService(appDatabase: appDatabase),
          connectivityProbe: (_) async => online,
        );
        addTearDown(queue.dispose);
        await configRepository.saveJwtToken('token-test');
        final clients = ClientRepository(
          appDatabase: appDatabase,
          syncQueueService: queue,
        );
        queue.registerRepository(clients);

        final now = DateTime.now();
        await clients.save(
          Client(
            fullName: 'Cliente Reconexion',
            documentId: '001-0002222-2',
            createdAt: now,
            updatedAt: now,
            syncStatus: SyncStatus.pending,
          ),
        );
        await queue.refreshScope('clients');

        final offlineProcessed = await queue.processQueue(
          includeDeferred: true,
        );
        expect(offlineProcessed, 0);

        online = true;
        await queue.refreshScope('clients');
        await queue.processQueue(includeDeferred: true);

        expect(apiClient.uploadedSyncIds.length, 1);
      },
    );

    test('reports_work_from_local_sqlite_test', () async {
      final db = await appDatabase.database;
      final now = DateTime.now().toIso8601String();

      final clientId = await db.insert(DatabaseSchema.clientsTable, {
        'sync_id': 'client-report-sync-1',
        'version': 1,
        'nombre': 'Cliente Reporte',
        'cedula': '001-0003333-3',
        'telefono': '8095550101',
        'direccion': 'Calle 1',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      final lotId = await db.insert(DatabaseSchema.lotsTable, {
        'sync_id': 'lot-report-sync-1',
        'version': 1,
        'manzana_numero': 'A',
        'solar_numero': '1',
        'metros_cuadrados': 100,
        'precio_por_metro': 1000,
        'estado': 'vendido',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      final saleId = await db.insert(DatabaseSchema.salesTable, {
        'sync_id': 'sale-report-sync-1',
        'version': 1,
        'cliente_id': clientId,
        'solar_id': lotId,
        'usuario_id': 1,
        'fecha_venta': now,
        'precio_venta': 100000,
        'inicial_porcentaje': 10,
        'inicial_monto': 10000,
        'monto_inicial_requerido': 10000,
        'monto_inicial_pagado': 10000,
        'monto_inicial_pendiente': 0,
        'saldo_financiado': 90000,
        'saldo_pendiente': 90000,
        'interes_mensual': 1,
        'cantidad_cuotas': 12,
        'estado': 'activa',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });
      await db.insert(DatabaseSchema.paymentsTable, {
        'sync_id': 'payment-report-sync-1',
        'version': 1,
        'venta_id': saleId,
        'cliente_id': clientId,
        'usuario_id': 1,
        'fecha_pago': now,
        'monto_pagado': 5000,
        'metodo_pago': 'efectivo',
        'tipo_pago': 'abono_inicial',
        'fecha_creacion': now,
        'fecha_actualizacion': now,
        'sync_status': DatabaseSchema.syncStatusSynced,
      });

      final repository = PaymentsRepository(appDatabase: appDatabase);
      final report = await repository.fetchClientPagareReport(clientId);

      expect(report.clientId, clientId);
      expect(report.items, isNotEmpty);
    });

    test('permissions_work_offline_test', () async {
      final authService = AuthService(
        appDatabase: appDatabase,
        syncConfigRepository: configRepository,
        httpClient: FakeBackendHttpClient(state: backendState),
      );
      await authService.signInHybrid(
        email: 'admin@gmail.com',
        password: 'Ayleen10',
      );
      await authService.signOut();
      backendState.offline = true;

      final offline = await authService.signInHybrid(
        email: 'admin@gmail.com',
        password: 'Ayleen10',
      );

      expect(offline.mode, AuthSignInMode.offline);
      expect(offline.user.permissions, isNotEmpty);
    });
  });
}

class _MemorySyncApiClient extends SyncApiClient {
  _MemorySyncApiClient();

  final Set<String> uploadedSyncIds = <String>{};

  @override
  Future<SyncUploadResponse> uploadQueuedRecords({
    required SyncSettings settings,
    required Map<String, List<Map<String, Object?>>> recordsByScope,
  }) async {
    final returned = <String, List<Map<String, dynamic>>>{};

    for (final entry in recordsByScope.entries) {
      final records = <Map<String, dynamic>>[];
      for (final record in entry.value) {
        final normalized = record.map((key, value) => MapEntry(key, value));
        final syncId = normalized['sync_id']?.toString().trim() ?? '';
        if (syncId.isNotEmpty) {
          uploadedSyncIds.add(syncId);
        }
        records.add(Map<String, dynamic>.from(normalized));
      }
      returned[entry.key] = records;
    }

    return SyncUploadResponse(returnedRecordsByScope: returned);
  }

  @override
  Future<SyncDownloadResponse> downloadChanges({
    required SyncSettings settings,
    DateTime? updatedSince,
    Map<String, DateTime?>? updatedSinceByScope,
  }) async {
    return const SyncDownloadResponse(
      recordsByScope: <String, List<Map<String, dynamic>>>{},
    );
  }
}

class _TimeoutOnLoginHttpClient implements HttpClient {
  _TimeoutOnLoginHttpClient(FakeBackendState state)
    : _delegate = FakeBackendHttpClient(state: state);

  final FakeBackendHttpClient _delegate;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _delegate.getUrl(url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    if (url.path.endsWith('/auth/login')) {
      return _TimeoutRequest();
    }
    return _delegate.postUrl(url);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      _delegate.noSuchMethod(invocation);
}

class _TimeoutRequest implements HttpClientRequest {
  final HttpHeaders _headers = _NoopHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  void write(Object? obj) {}

  @override
  Future<HttpClientResponse> close() {
    return Future<HttpClientResponse>.error(
      TimeoutException('forced-timeout-login'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopHeaders implements HttpHeaders {
  ContentType? _contentType;

  @override
  ContentType? get contentType => _contentType;

  @override
  set contentType(ContentType? value) {
    _contentType = value;
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
