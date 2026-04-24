import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/app_flags.dart';
import '../resilience/app_paths.dart';
import '../utils/client_data_guard.dart';
import 'database_schema.dart';

class AppDatabase {
  AppDatabase._({
    String? customDatabasePath,
    AppPaths? appPaths,
    Future<String?> Function(DatabaseFactory)? legacyDatabaseLocator,
  }) : _customDatabasePath = customDatabasePath,
       _appPaths = appPaths,
       _legacyDatabaseLocator = legacyDatabaseLocator;

  factory AppDatabase.test(String databasePath) {
    return AppDatabase._(customDatabasePath: databasePath);
  }

  factory AppDatabase.forStorage({
    required AppPaths appPaths,
    Future<String?> Function(DatabaseFactory)? legacyDatabaseLocator,
  }) {
    return AppDatabase._(
      appPaths: appPaths,
      legacyDatabaseLocator: legacyDatabaseLocator,
    );
  }

  static final AppDatabase instance = AppDatabase._();

  final String? _customDatabasePath;
  final AppPaths? _appPaths;
  final Future<String?> Function(DatabaseFactory)? _legacyDatabaseLocator;
  Database? _database;
  Future<Database>? _openingDatabase;

  AppPaths get appPaths => _appPaths ?? AppPaths();

  Future<void> initialize() async {
    await database;
  }

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final pendingDatabase = _openingDatabase;
    if (pendingDatabase != null) {
      return pendingDatabase;
    }

    final stopwatch = Stopwatch()..start();
    print('🧠 INIT DB...');
    final openFuture = _openDatabase();
    _openingDatabase = openFuture;
    try {
      final openedDatabase = await openFuture;
      _database = openedDatabase;

      print('✅ DB ABIERTA: $openedDatabase');
      await _logTables(openedDatabase);
      await _runWritableProbe(openedDatabase);

      if (kDebugMode) {
        debugPrint(
          'Base de datos lista en ${stopwatch.elapsedMilliseconds} ms.',
        );
      }
      return openedDatabase;
    } finally {
      if (identical(_openingDatabase, openFuture)) {
        _openingDatabase = null;
      }
    }
  }

  Future<String> get databasePath async {
    _initializeFactory();

    if (_customDatabasePath != null) {
      final customDatabasePath = _customDatabasePath;
      await Directory(path.dirname(customDatabasePath)).create(recursive: true);
      return customDatabasePath;
    }

    await appPaths.ensureCriticalDirectories();
    final targetPath = appPaths.databasePath;
    await _migrateLegacyDatabaseIfNeeded(targetPath);
    return targetPath;
  }

  Future<void> close() async {
    final currentDatabase = _database;
    _database = null;
    _openingDatabase = null;

    if (currentDatabase != null) {
      try {
        await currentDatabase.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {
        // Best effort checkpoint before close.
      }
      await currentDatabase.close();
    }
  }

  Future<Database> _openDatabase() async {
    final dbPath = await databasePath;
    print('📁 DB PATH: $dbPath');

    return databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: DatabaseSchema.databaseVersion,
        onConfigure: (db) async => DatabaseSchema.configure(db),
        onCreate: (db, version) async {
          print('🔥 CREANDO TABLAS...');
          await DatabaseSchema.createTables(db);
          await DatabaseSchema.seedDefaults(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await DatabaseSchema.migrate(db, oldVersion, newVersion);
        },
        onDowngrade: (db, oldVersion, newVersion) async {
          throw UnsupportedError(
            'No se admite abrir una base con una version de esquema superior a la soportada por esta compilacion.',
          );
        },
        onOpen: (db) async {
          await DatabaseSchema.seedDefaults(db);
          if (isProductionMode && _customDatabasePath == null) {
            await _cleanProductionClients(db);
          }
        },
      ),
    );
  }

  Future<void> _logTables(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    print('📦 TABLAS: $tables');
  }

  Future<void> _runWritableProbe(Database db) async {
    try {
      await db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();
        final probeDocument =
            'DB-PROBE-${DateTime.now().microsecondsSinceEpoch}';
        final probeId = await txn.insert(DatabaseSchema.clientsTable, {
          'sync_id': 'db-probe-${DateTime.now().microsecondsSinceEpoch}',
          'nombre': 'TEST',
          'cedula': probeDocument,
          'telefono': '8090000000',
          'direccion': 'sqlite-probe',
          'fecha_creacion': now,
          'fecha_actualizacion': now,
          'deleted_at': null,
          'sync_status': DatabaseSchema.syncStatusPending,
        });
        await txn.delete(
          DatabaseSchema.clientsTable,
          where: 'id = ?',
          whereArgs: [probeId],
        );
      });
      print('✅ INSERT OK');
    } catch (error, stackTrace) {
      print('💥 ERROR SQLITE: $error');
      print(stackTrace);
      rethrow;
    }
  }

  void _initializeFactory() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  Future<void> _migrateLegacyDatabaseIfNeeded(String targetPath) async {
    if (!allowLegacyMigration) {
      return;
    }

    final targetFile = File(targetPath);
    if (await targetFile.exists() && await targetFile.length() > 0) {
      return;
    }

    final legacyPath = await _resolveLegacyDatabasePath(targetPath);
    if (legacyPath == null) {
      return;
    }

    final normalizedTarget = path.normalize(targetPath);
    final normalizedLegacy = path.normalize(legacyPath);
    if (normalizedTarget == normalizedLegacy) {
      return;
    }

    final legacyFile = File(legacyPath);
    if (!await legacyFile.exists() || await legacyFile.length() <= 0) {
      return;
    }

    await targetFile.parent.create(recursive: true);
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    await _moveFile(legacyFile, targetFile);
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final legacySidecar = File('$legacyPath$suffix');
      if (!await legacySidecar.exists()) {
        continue;
      }

      final targetSidecar = File('$targetPath$suffix');
      if (await targetSidecar.exists()) {
        await targetSidecar.delete();
      }
      await _moveFile(legacySidecar, targetSidecar);
    }
  }

  Future<void> _cleanProductionClients(Database db) async {
    try {
      final rows = await db.query(
        DatabaseSchema.clientsTable,
        columns: [
          'id',
          'sync_id',
          'nombre',
          'cedula',
          'sync_status',
          'fecha_actualizacion',
          'deleted_at',
        ],
      );
      if (rows.isEmpty) {
        return;
      }

      final now = DateTime.now();
      final nowIso = now.toIso8601String();

      await db.transaction((txn) async {
        final activeRows = <Map<String, Object?>>[];

        for (final row in rows) {
          final deletedAt = row['deleted_at']?.toString().trim();
          if (deletedAt != null && deletedAt.isNotEmpty) {
            continue;
          }
          activeRows.add(row);
        }

        if (activeRows.isEmpty) {
          return;
        }

        final candidatesByDocument = <String, List<Map<String, Object?>>>{};
        final invalidIds = <int>{};

        for (final row in activeRows) {
          final id = row['id'] as int?;
          if (id == null) {
            continue;
          }

          final fullName = (row['nombre']?.toString() ?? '').trim();
          final documentRaw = (row['cedula']?.toString() ?? '');
          final documentId = documentRaw.trim();
          final syncId = (row['sync_id']?.toString() ?? '').trim();

          final shouldDelete =
              ClientDataGuard.isTestLikeName(fullName) ||
              !ClientDataGuard.hasValidDocumentId(documentId) ||
              !ClientDataGuard.hasValidSyncId(syncId);

          if (shouldDelete) {
            invalidIds.add(id);
            continue;
          }

          candidatesByDocument
              .putIfAbsent(documentId, () => <Map<String, Object?>>[])
              .add(row);
        }

        Future<void> softDelete(int id) async {
          await txn.update(
            DatabaseSchema.clientsTable,
            {
              'deleted_at': nowIso,
              'fecha_actualizacion': nowIso,
              'sync_status': DatabaseSchema.syncStatusSynced,
              // Keep UNIQUE(cedula) from blocking normalization of live rows.
              'cedula': '__DELETED__${id}',
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }

        for (final id in invalidIds) {
          await softDelete(id);
        }

        int pickCanonicalId(List<Map<String, Object?>> group) {
          group.sort((left, right) {
            final leftSync = (left['sync_id']?.toString() ?? '').trim();
            final rightSync = (right['sync_id']?.toString() ?? '').trim();
            if (leftSync.isEmpty != rightSync.isEmpty) {
              return leftSync.isEmpty ? 1 : -1;
            }

            final leftUpdated = DateTime.tryParse(
              (left['fecha_actualizacion']?.toString() ?? '').trim(),
            );
            final rightUpdated = DateTime.tryParse(
              (right['fecha_actualizacion']?.toString() ?? '').trim(),
            );
            if (leftUpdated != null && rightUpdated != null) {
              final cmp = rightUpdated.compareTo(leftUpdated);
              if (cmp != 0) {
                return cmp;
              }
            } else if (leftUpdated != null) {
              return -1;
            } else if (rightUpdated != null) {
              return 1;
            }

            final leftId = left['id'] as int? ?? 0;
            final rightId = right['id'] as int? ?? 0;
            return rightId.compareTo(leftId);
          });

          return group.first['id'] as int? ?? 0;
        }

        // Resolve duplicates by trimmed document id.
        for (final entry in candidatesByDocument.entries) {
          final group = entry.value;
          if (group.isEmpty) {
            continue;
          }

          final canonicalId = group.length == 1
              ? (group.first['id'] as int? ?? 0)
              : pickCanonicalId(group);
          for (final row in group) {
            final id = row['id'] as int?;
            if (id == null || id == 0) {
              continue;
            }
            if (id == canonicalId) {
              continue;
            }
            await softDelete(id);
          }

          if (canonicalId == 0) {
            continue;
          }

          final canonicalRow = group.firstWhere(
            (row) => (row['id'] as int?) == canonicalId,
            orElse: () => group.first,
          );

          final rawName = (canonicalRow['nombre']?.toString() ?? '');
          final rawDocument = (canonicalRow['cedula']?.toString() ?? '');
          final rawSyncId = (canonicalRow['sync_id']?.toString() ?? '');

          final normalizedName = rawName.trim();
          final normalizedDoc = rawDocument.trim();
          final normalizedSync = rawSyncId.trim();

          // If a previously deleted row already holds the trimmed document id,
          // rewrite it to a placeholder so UNIQUE(cedula) doesn't block.
          if (rawDocument != normalizedDoc) {
            final conflict = await txn.query(
              DatabaseSchema.clientsTable,
              columns: ['id', 'deleted_at'],
              where: 'cedula = ? AND id <> ?',
              whereArgs: [normalizedDoc, canonicalId],
              limit: 1,
            );
            if (conflict.isNotEmpty) {
              final conflictId = conflict.first['id'] as int?;
              if (conflictId != null) {
                await txn.update(
                  DatabaseSchema.clientsTable,
                  {'cedula': '__CEDULA_CONFLICT__${conflictId}'},
                  where: 'id = ?',
                  whereArgs: [conflictId],
                );
              }
            }
          }

          final values = <String, Object?>{};
          if (rawName != normalizedName) {
            values['nombre'] = normalizedName;
          }
          if (rawDocument != normalizedDoc) {
            values['cedula'] = normalizedDoc;
          }
          if (rawSyncId != normalizedSync) {
            values['sync_id'] = normalizedSync;
          }

          if (values.isNotEmpty) {
            await txn.update(
              DatabaseSchema.clientsTable,
              values,
              where: 'id = ?',
              whereArgs: [canonicalId],
            );
          }
        }
      });
    } catch (_) {
      // Best-effort cleanup. Startup must not fail because of cleanup.
    }
  }

  Future<String?> _resolveLegacyDatabasePath(String targetPath) async {
    final customLocator = _legacyDatabaseLocator;
    if (customLocator != null) {
      return customLocator(databaseFactory);
    }

    final legacyDirectory = await databaseFactory.getDatabasesPath();
    await Directory(legacyDirectory).create(recursive: true);
    return path.join(legacyDirectory, DatabaseSchema.databaseName);
  }

  Future<void> _moveFile(File source, File target) async {
    try {
      await source.rename(target.path);
    } on FileSystemException {
      await source.copy(target.path);
      await source.delete();
    }
  }
}
