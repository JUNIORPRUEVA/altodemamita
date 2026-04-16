import 'package:flutter/material.dart';
import '../services/backup_service.dart';

/// Observer for app lifecycle to trigger auto backups on startup/shutdown
class BackupLifecycleObserver extends WidgetsBindingObserver {
  BackupLifecycleObserver({required this.backupService});

  final BackupService backupService;
  bool _hasPerformedStartupBackup = false;

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.resumed:
        // App just came to foreground - perform startup backup once
        if (!_hasPerformedStartupBackup) {
          print('[LIFECYCLE] App resumed - performing startup backup if configured');
          await _performStartupBackup();
          _hasPerformedStartupBackup = true;
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App is being backgrounded or closed
        print('[LIFECYCLE] App paused/closed - performing shutdown backup if configured');
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
      if (config.autoBackupEnabled && config.autoBackupOnStartup) {
        print('[STARTUP_BACKUP] Iniciando backup automático en startup...');
        final result = await backupService.createBackup(backupType: 'startup');
        if (result.success) {
          print('[STARTUP_BACKUP] ✓ Backup de startup creado: ${result.metadata.formattedDate}');
        } else {
          print('[STARTUP_BACKUP] ERROR: ${result.errorMessage}');
        }
      } else {
        print('[STARTUP_BACKUP] Backup automático deshabilitado o no configurado para startup');
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
          print('[SHUTDOWN_BACKUP] ✓ Backup de shutdown creado: ${result.metadata.formattedDate}');
        } else {
          print('[SHUTDOWN_BACKUP] ERROR: ${result.errorMessage}');
        }
      } else {
        print('[SHUTDOWN_BACKUP] Backup automático deshabilitado o no configurado para shutdown');
      }
    } catch (e) {
      print('[SHUTDOWN_BACKUP] Error en backup de shutdown: $e');
    }
  }
}
