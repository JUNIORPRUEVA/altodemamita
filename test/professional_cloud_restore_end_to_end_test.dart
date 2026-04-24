import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/services/professional_backup/backup_restore_service.dart';
import 'package:sistema_solares/services/professional_backup/cloud_restore_agent.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';
import 'package:test/test.dart';

class _FakeSyncConfigRepository extends SyncConfigRepository {
  _FakeSyncConfigRepository(this._settings);

  final SyncSettings _settings;

  @override
  Future<SyncSettings> loadSettings() async => _settings;
}

void main() {
  group('Professional cloud restore (end-to-end)', () {
    test('restaura desde cloud (list + download) a una DB borrada', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'sistema_solares_cloud_restore_e2e_',
      );
      final supportDirectory = path.join(tempDirectory.path, 'support');
      final databasePath = path.join(tempDirectory.path, 'data', 'app.db');

      final appDatabase = AppDatabase.test(databasePath);
      final appPaths = AppPaths(supportDirectory: supportDirectory);

      HttpServer? server;
      StreamSubscription<HttpRequest>? serverSubscription;
      HttpClient? httpClient;

      try {
        await appDatabase.initialize();
        final db = await appDatabase.database;

        const sentinelKey = 'sentinel_professional_cloud_restore_key';
        final now = DateTime.now().toIso8601String();
        await db.rawInsert(
          'INSERT OR REPLACE INTO ${DatabaseSchema.settingsTable} '
          '(clave, valor, fecha_actualizacion) VALUES (?, ?, ?)',
          [sentinelKey, 'from_cloud', now],
        );

        // Close the DB before packaging it to ensure a consistent snapshot.
        await appDatabase.close();

        final dbFileForZip = File(databasePath);
        expect(await dbFileForZip.exists(), isTrue);
        expect(await dbFileForZip.length(), greaterThan(0));

        final zipId = 'backup_cloud_test.db.zip';
        final zipFile = File(path.join(tempDirectory.path, zipId));

        final dbBytes = await dbFileForZip.readAsBytes();
        final archive = Archive()
          ..addFile(ArchiveFile('app.db', dbBytes.length, dbBytes));
        final zipBytes = ZipEncoder().encode(archive);
        if (zipBytes == null || zipBytes.isEmpty) {
          throw StateError('No se pudo generar el ZIP de prueba.');
        }
        await zipFile.writeAsBytes(zipBytes, flush: true);
        expect(await zipFile.exists(), isTrue);
        expect(await zipFile.length(), greaterThan(0));

        // Simulate catastrophic local loss.
        final dbFile = File(databasePath);
        if (await dbFile.exists()) {
          await dbFile.delete();
        }
        for (final suffix in ['-wal', '-shm', '-journal']) {
          final sidecar = File('$databasePath$suffix');
          if (await sidecar.exists()) {
            await sidecar.delete();
          }
        }

        // Fake backend API.
        final localServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        server = localServer;
        final baseUrl = 'http://127.0.0.1:${localServer.port}';
        const token = 'test-token';

        serverSubscription = localServer.listen((request) async {
          try {
            final auth = request.headers.value(HttpHeaders.authorizationHeader);
            if (auth != 'Bearer $token') {
              request.response.statusCode = HttpStatus.unauthorized;
              await request.response.close();
              return;
            }

            if (request.method == 'GET' &&
                request.uri.path == '/api/system/backup/list') {
              request.response.statusCode = HttpStatus.ok;
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                jsonEncode({
                  'items': [
                    {
                      'id': zipId,
                      'filename': zipId,
                      'sizeBytes': await zipFile.length(),
                      'modifiedAt': DateTime.now().toIso8601String(),
                    },
                  ],
                }),
              );
              await request.response.close();
              return;
            }

            if (request.method == 'GET' &&
                request.uri.path == '/api/system/backup/download/$zipId') {
              request.response.statusCode = HttpStatus.ok;
              request.response.headers.contentType = ContentType(
                'application',
                'zip',
              );
              await request.response.addStream(zipFile.openRead());
              await request.response.close();
              return;
            }

            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
          } catch (_) {
            try {
              request.response.statusCode = HttpStatus.internalServerError;
              await request.response.close();
            } catch (_) {}
          }
        });

        httpClient = HttpClient();

        final settings = SyncSettings(
          baseUrl: baseUrl,
          jwtToken: token,
          queueRetryInterval: const Duration(seconds: 10),
          realtimePollingInterval: const Duration(seconds: 5),
          conflictStrategy: SyncConflictStrategy.manual,
          deviceId: 'test-device',
        );

        final cloudAgent = CloudRestoreAgent(
          syncConfigRepository: _FakeSyncConfigRepository(settings),
          httpClient: httpClient,
        );

        final restoreService = BackupRestoreService(
          appDatabase: appDatabase,
          appPaths: appPaths,
          cloudRestoreAgent: cloudAgent,
        );

        final listed = await restoreService.listCloudBackups();
        expect(listed.map((e) => e.id), contains(zipId));

        final result = await restoreService.restoreCloud(backupId: zipId);
        expect(result.success, isTrue);

        await appDatabase.close();
        await appDatabase.initialize();

        final restoredDb = await appDatabase.database;
        final rows = await restoredDb.rawQuery(
          'SELECT valor FROM ${DatabaseSchema.settingsTable} WHERE clave = ?',
          [sentinelKey],
        );

        expect(rows, hasLength(1));
        expect(rows.first['valor'], 'from_cloud');
      } finally {
        httpClient?.close(force: true);
        await serverSubscription?.cancel();
        await server?.close(force: true);
        await appDatabase.close();
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      }
    });
  });
}
