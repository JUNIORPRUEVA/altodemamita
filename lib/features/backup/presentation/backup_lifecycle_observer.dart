import 'dart:async';

import 'package:flutter/material.dart';
import '../services/backup_service.dart';

/// Observer for app lifecycle to trigger auto backups on startup/shutdown
class BackupLifecycleObserver extends WidgetsBindingObserver {
  BackupLifecycleObserver({required this.backupService});

  final BackupService backupService;
  bool _hasPerformedStartupBackup = false;
  Timer? _startupBackupTimer;

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.resumed:
        // App just came to foreground - perform startup backup once
        if (!_hasPerformedStartupBackup) {
          print(
            '[LIFECYCLE] App resumed - performing startup backup if configured',
          );
          _hasPerformedStartupBackup = true;

          // Do not block app startup/resume with heavy IO.
          // BackupService closes/reopens SQLite; deferring avoids stalling the UI
          // and reduces perceived startup time.
          _startupBackupTimer?.cancel();
          _startupBackupTimer = Timer(const Duration(seconds: 30), () {
            unawaited(_performStartupBackup());
          });
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Desktop apps can enter paused/hidden while still running.
        // Avoid closing/reopening SQLite here because it can race with sync.
        print('[LIFECYCLE] App paused/hidden - omitiendo backup de shutdown');
        break;
      case AppLifecycleState.detached:
        // App is being closed
        print(
          '[LIFECYCLE] App detached - performing shutdown backup if configured',
        );
        await _performShutdownBackup();
        break;
      case AppLifecycleState.inactive:
        // App is inactive (transitioning between states)
        break;
    }
  }

  Future<void> _performStartupBackup() async {
    try {
      final config = await backupService.getConfig();

      // Throttle: avoid repeated backups on quick restarts.
      final lastBackup = config.lastBackupTimestamp;
      if (lastBackup != null) {
        final elapsed = DateTime.now().difference(lastBackup);
        if (elapsed.inMinutes < 10) {
          print(
            '[STARTUP_BACKUP] Omitido: ya se ejecutó un backup recientemente (${elapsed.inMinutes} min)',
          );
          return;
        }
      }

      if (config.autoBackupEnabled && config.autoBackupOnStartup) {
        print('[STARTUP_BACKUP] Iniciando backup automático en startup...');
        final result = await backupService.createBackup(backupType: 'startup');
        if (result.success) {
          print(
            '[STARTUP_BACKUP] ✓ Backup de startup creado: ${result.metadata.formattedDate}',
          );
        } else {
          print('[STARTUP_BACKUP] ERROR: ${result.errorMessage}');
        }
      } else {
        print(
          '[STARTUP_BACKUP] Backup automático deshabilitado o no configurado para startup',
        );
      }
    } catch (e) {
      print('[STARTUP_BACKUP] Error en backup de startup: $e');
    }
  }

  Future<void> _performShutdownBackup() async {
    try {
      final config = await backupService.getConfig();
      if (config.autoBackupEnabled && config.autoBackupOnShutdown) {
        print('[SHUTDOWN_BACKUP] Iniciando backup automático en shutdown...');
        final result = await backupService.createBackup(backupType: 'shutdown');
        if (result.success) {
          print(
            '[SHUTDOWN_BACKUP] ✓ Backup de shutdown creado: ${result.metadata.formattedDate}',
          );
        } else {
          print('[SHUTDOWN_BACKUP] ERROR: ${result.errorMessage}');
        }
      } else {
        print(
          '[SHUTDOWN_BACKUP] Backup automático deshabilitado o no configurado para shutdown',
        );
      }
    } catch (e) {
      print('[SHUTDOWN_BACKUP] Error en backup de shutdown: $e');
    }
  }
}
