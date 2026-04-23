import 'dart:async';

import 'package:flutter/widgets.dart';

import 'backup_service.dart';

class ProfessionalBackupLifecycleObserver extends WidgetsBindingObserver {
  ProfessionalBackupLifecycleObserver({required BackupService backupService})
    : _backupService = backupService;

  final BackupService _backupService;
  bool _shutdownBackupQueued = false;

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state != AppLifecycleState.detached) {
      return;
    }

    if (_shutdownBackupQueued) {
      return;
    }
    _shutdownBackupQueued = true;

    unawaited(_backupService.createLocalBackup(trigger: BackupTrigger.appShutdown));
  }
}
