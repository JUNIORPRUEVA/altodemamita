import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../core/database/app_database.dart';
import '../core/database/database_schema.dart';
import '../core/database/platform_database_factory_web.dart'
    if (dart.library.io) '../core/database/platform_database_factory_io.dart';
import '../core/theme/app_theme.dart';

class PwaRuntimeDiagnosticApp extends StatefulWidget {
  const PwaRuntimeDiagnosticApp({super.key});

  @override
  State<PwaRuntimeDiagnosticApp> createState() =>
      _PwaRuntimeDiagnosticAppState();
}

class _PwaRuntimeDiagnosticAppState extends State<PwaRuntimeDiagnosticApp> {
  static const _databasePath =
      '/SistemaSolares/data/database/pwa_runtime_gate.db';
  static const _persistSyncId = 'pwa-runtime-persist-marker';
  static const _workSyncId = 'pwa-runtime-work-row';

  final Map<String, _DiagnosticStatus> _statuses = {
    'FACTORY': _DiagnosticStatus.pending,
    'OPEN': _DiagnosticStatus.pending,
    'SCHEMA': _DiagnosticStatus.pending,
    'INSERT': _DiagnosticStatus.pending,
    'READ': _DiagnosticStatus.pending,
    'UPDATE': _DiagnosticStatus.pending,
    'DELETE': _DiagnosticStatus.pending,
    'REOPEN': _DiagnosticStatus.pending,
    'PERSIST_AFTER_REFRESH': _DiagnosticStatus.pending,
  };
  String _summary = 'RUNNING';
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_runDiagnostic());
  }

  Future<void> _runDiagnostic() async {
    final database = AppDatabase.test(_databasePath);
    try {
      final factory = createPlatformDatabaseFactory();
      _mark('FACTORY', _DiagnosticStatus.pass);
      _log('FACTORY', 'databaseFactoryFfiWebNoWebWorker');
      _log('FACTORY_DETAILS', factory);

      await database.initialize();
      final db = await database.database;
      _mark('OPEN', _DiagnosticStatus.pass);

      await _verifySchema(db);
      _mark('SCHEMA', _DiagnosticStatus.pass);

      final hadPersistedMarker = await _hasClient(db, _persistSyncId);
      _log('PERSIST_MARKER_EXISTED', hadPersistedMarker);
      await _upsertPersistMarker(db);
      _mark(
        'PERSIST_AFTER_REFRESH',
        hadPersistedMarker ? _DiagnosticStatus.pass : _DiagnosticStatus.warn,
      );

      await _resetWorkRow(db);
      await db.insert(DatabaseSchema.clientsTable, _clientRow(_workSyncId));
      _mark('INSERT', _DiagnosticStatus.pass);

      final inserted = await _readClientName(db, _workSyncId);
      if (inserted != 'PWA RUNTIME WORK ROW') {
        throw StateError('read mismatch after insert');
      }
      _mark('READ', _DiagnosticStatus.pass);

      await db.update(
        DatabaseSchema.clientsTable,
        {
          'nombre': 'PWA RUNTIME UPDATED',
          'fecha_actualizacion': DateTime.now().toIso8601String(),
        },
        where: 'sync_id = ?',
        whereArgs: [_workSyncId],
      );
      final updated = await _readClientName(db, _workSyncId);
      if (updated != 'PWA RUNTIME UPDATED') {
        throw StateError('read mismatch after update');
      }
      _mark('UPDATE', _DiagnosticStatus.pass);

      await db.delete(
        DatabaseSchema.clientsTable,
        where: 'sync_id = ?',
        whereArgs: [_workSyncId],
      );
      if (await _hasClient(db, _workSyncId)) {
        throw StateError('delete did not remove work row');
      }
      _mark('DELETE', _DiagnosticStatus.pass);

      await database.close();
      final reopenedDatabase = AppDatabase.test(_databasePath);
      await reopenedDatabase.initialize();
      final reopened = await reopenedDatabase.database;
      if (!await _hasClient(reopened, _persistSyncId)) {
        throw StateError('persist marker missing after reopen');
      }
      _mark('REOPEN', _DiagnosticStatus.pass);
      await reopenedDatabase.close();

      _summary =
          _statuses.values.every((status) => status == _DiagnosticStatus.pass)
          ? 'PASS'
          : 'PASS_WITH_REFRESH_WARMUP';
      _log('SUMMARY', _summary);
    } catch (error, stackTrace) {
      _summary = 'FAIL';
      _error = '$error';
      for (final entry in _statuses.entries) {
        if (entry.value == _DiagnosticStatus.pending) {
          _statuses[entry.key] = _DiagnosticStatus.fail;
        }
      }
      debugPrint('[PWA_RUNTIME_GATE] FAIL $error');
      debugPrint('$stackTrace');
    } finally {
      await database.close();
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _verifySchema(Database db) async {
    final versionRows = await db.rawQuery('PRAGMA user_version');
    final version = (versionRows.first.values.first as num?)?.toInt() ?? 0;
    if (version <= 0) {
      throw StateError('schema version was not created');
    }

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final tableNames = tables
        .map((row) => row['name']?.toString() ?? '')
        .toSet();
    for (final requiredTable in [
      DatabaseSchema.clientsTable,
      DatabaseSchema.lotsTable,
      DatabaseSchema.salesTable,
      DatabaseSchema.installmentsTable,
      DatabaseSchema.paymentsTable,
      DatabaseSchema.syncQueueTable,
    ]) {
      if (!tableNames.contains(requiredTable)) {
        throw StateError('missing table $requiredTable');
      }
    }
  }

  Future<void> _upsertPersistMarker(Database db) async {
    await db.delete(
      DatabaseSchema.clientsTable,
      where: 'sync_id = ?',
      whereArgs: [_persistSyncId],
    );
    await db.insert(DatabaseSchema.clientsTable, _clientRow(_persistSyncId));
  }

  Future<void> _resetWorkRow(Database db) {
    return db.delete(
      DatabaseSchema.clientsTable,
      where: 'sync_id = ?',
      whereArgs: [_workSyncId],
    );
  }

  Map<String, Object?> _clientRow(String syncId) {
    final now = DateTime.now().toIso8601String();
    return {
      'sync_id': syncId,
      'nombre': syncId == _workSyncId
          ? 'PWA RUNTIME WORK ROW'
          : 'PWA RUNTIME PERSIST MARKER',
      'cedula': syncId == _workSyncId ? 'PWA-WORK-0001' : 'PWA-PERSIST-0001',
      'telefono': '8090000000',
      'direccion': 'pwa runtime gate',
      'fecha_creacion': now,
      'fecha_actualizacion': now,
      'deleted_at': null,
      'sync_status': DatabaseSchema.syncStatusPending,
    };
  }

  Future<String?> _readClientName(Database db, String syncId) async {
    final rows = await db.query(
      DatabaseSchema.clientsTable,
      columns: ['nombre'],
      where: 'sync_id = ?',
      whereArgs: [syncId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['nombre']?.toString();
  }

  Future<bool> _hasClient(Database db, String syncId) async {
    final rows = await db.query(
      DatabaseSchema.clientsTable,
      columns: ['id'],
      where: 'sync_id = ?',
      whereArgs: [syncId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  void _mark(String key, _DiagnosticStatus status) {
    _statuses[key] = status;
    _log(key, status.label);
    if (mounted) {
      setState(() {});
    }
  }

  void _log(String key, Object value) {
    debugPrint('[PWA_RUNTIME_GATE] $key=$value');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        appBar: AppBar(title: const Text('PWA Runtime Gate')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'SUMMARY: $_summary',
              key: const ValueKey('pwa-runtime-summary'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            for (final entry in _statuses.entries)
              ListTile(
                dense: true,
                leading: Icon(entry.value.icon, color: entry.value.color),
                title: Text('${entry.key}: ${entry.value.label}'),
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              SelectableText('ERROR: $_error'),
            ],
          ],
        ),
      ),
    );
  }
}

enum _DiagnosticStatus {
  pending('PENDING', Icons.schedule_rounded, Colors.orange),
  pass('PASS', Icons.check_circle_rounded, Colors.green),
  warn('WARN', Icons.info_rounded, Colors.amber),
  fail('FAIL', Icons.error_rounded, Colors.red);

  const _DiagnosticStatus(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}
