import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../backup/data/backup_config_repository.dart';
import '../../backup/presentation/backup_page.dart' as backup_feature;
import '../../backup/services/backup_service.dart';
import '../../backup/services/disk_detection_service.dart';

class BackupPage extends StatelessWidget {
  BackupPage({super.key})
    : _diskDetectionService = DiskDetectionService(),
      _backupService = BackupService(
        appDatabase: AppDatabase.instance,
        configRepository: BackupConfigRepository(),
        diskDetectionService: DiskDetectionService(),
      );

  final DiskDetectionService _diskDetectionService;
  final BackupService _backupService;

  @override
  Widget build(BuildContext context) {
    return backup_feature.BackupPage(
      backupService: _backupService,
      diskDetectionService: _diskDetectionService,
    );
  }
}
