import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;

import '../../core/database/app_database.dart';
import '../../core/resilience/app_paths.dart';
import '../sync/sync_config_repository.dart';
import 'backup_validator_agent.dart';
import 'database_activity_guard.dart';

class CloudBackupUploadResult {
  const CloudBackupUploadResult({
    required this.success,
    required this.statusCode,
    required this.remoteFilename,
    this.message,
  });

  final bool success;
  final int statusCode;
  final String remoteFilename;
  final String? message;
}

class CloudBackupAgent {
  CloudBackupAgent({
    required AppDatabase appDatabase,
    required AppPaths appPaths,
    SyncConfigRepository? syncConfigRepository,
    HttpClient? httpClient,
    BackupValidatorAgent? validator,
    DatabaseActivityGuard? activityGuard,
  }) : _appDatabase = appDatabase,
       _appPaths = appPaths,
       _syncConfigRepository = syncConfigRepository ?? SyncConfigRepository(),
       _httpClient = httpClient ?? HttpClient(),
       _validator = validator ?? const BackupValidatorAgent(),
       _activityGuard = activityGuard ?? const DatabaseActivityGuard() {
    _httpClient.connectionTimeout = const Duration(seconds: 20);
    _httpClient.idleTimeout = const Duration(seconds: 30);
  }

  final AppDatabase _appDatabase;
  final AppPaths _appPaths;
  final SyncConfigRepository _syncConfigRepository;
  final HttpClient _httpClient;
  final BackupValidatorAgent _validator;
  final DatabaseActivityGuard _activityGuard;

  Future<CloudBackupUploadResult> createAndUploadDailyBackup({
    required DateTime date,
  }) async {
    final dateLabel = _calendarDate(date);
    final innerDbName = 'backup_cloud_$dateLabel.db';
    final zipName = '$innerDbName.zip';

    final tempDir = Directory(_appPaths.tempDirectory);
    await tempDir.create(recursive: true);

    final snapshotDbPath = path.join(tempDir.path, 'cloud_snapshot_$dateLabel.db');
    final zipPath = path.join(tempDir.path, 'cloud_backup_$dateLabel.zip');

    final sourcePath = await _appDatabase.databasePath;
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw StateError('Base de datos local no encontrada.');
    }

    await _activityGuard.waitForNoActiveWriters(databasePath: sourcePath);

    print('[PRO-BACKUP] Preparando snapshot para nube: $zipName');

    // Create a consistent snapshot by checkpointing and closing the DB briefly.
    try {
      final db = await _appDatabase.database;
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // Best effort.
    }

    await _appDatabase.close();

    try {
      final snapshotFile = await sourceFile.copy(snapshotDbPath);
      await _validator.validateSQLiteDbFile(snapshotFile);

      print('[PRO-BACKUP] Empaquetando ZIP: $zipName');

      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      encoder.addFile(snapshotFile, innerDbName);
      encoder.close();

      final zipFile = File(zipPath);
      await _validator.validateZipFile(zipFile);

      print('[PRO-BACKUP] Subiendo ZIP al backend: $zipName');

      final result = await _uploadZip(
        zipFile: zipFile,
        uploadFilename: zipName,
      );

      if (result.success) {
        print('[PRO-BACKUP] Upload OK: $zipName');
      } else {
        print(
          '[PRO-BACKUP] Upload FAIL: $zipName (status=${result.statusCode})',
        );
      }
      return result;
    } finally {
      await _appDatabase.initialize();
      // Cleanup temp files best-effort.
      try {
        await File(snapshotDbPath).delete();
      } catch (_) {}
      try {
        await File(zipPath).delete();
      } catch (_) {}
    }
  }

  Future<CloudBackupUploadResult> _uploadZip({
    required File zipFile,
    required String uploadFilename,
  }) async {
    final settings = await _syncConfigRepository.loadSettings();
    if (!settings.isConfigured) {
      throw StateError('La sincronización no está configurada (baseUrl/token).');
    }

    final uri = _buildUploadUri(settings.normalizedBaseUrl);

    final boundary = '----sistemaSolaresBoundary${DateTime.now().microsecondsSinceEpoch}';
    final request = await _httpClient.postUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${settings.jwtToken}');
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'multipart/form-data; boundary=$boundary',
    );

    void writeString(String value) {
      request.add(utf8.encode(value));
    }

    writeString('--$boundary\r\n');
    writeString(
      'Content-Disposition: form-data; name="file"; filename="$uploadFilename"\r\n',
    );
    writeString('Content-Type: application/zip\r\n\r\n');

    await request.addStream(zipFile.openRead());

    writeString('\r\n--$boundary--\r\n');

    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return CloudBackupUploadResult(
        success: true,
        statusCode: response.statusCode,
        remoteFilename: uploadFilename,
        message: body.trim().isEmpty ? null : body,
      );
    }

    return CloudBackupUploadResult(
      success: false,
      statusCode: response.statusCode,
      remoteFilename: uploadFilename,
      message: body,
    );
  }

  static Uri _buildUploadUri(String normalizedBaseUrl) {
    final base = Uri.parse(normalizedBaseUrl);
    final trimmedPath = base.path.replaceAll(RegExp(r'/+$'), '');
    final hasApiPrefix = trimmedPath == '/api' || trimmedPath.endsWith('/api');
    final prefix = hasApiPrefix ? trimmedPath : '$trimmedPath/api';

    // Ensure leading slash for a valid absolute path.
    final normalizedPrefix = prefix.isEmpty
        ? '/api'
        : (prefix.startsWith('/') ? prefix : '/$prefix');

    return base.replace(path: '$normalizedPrefix/system/backup/upload');
  }

  static String _calendarDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
