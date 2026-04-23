import 'dart:async';

import 'professional_backup_settings.dart';

typedef CloudBackupJob = Future<void> Function();

class BackupSchedulerAgent {
  BackupSchedulerAgent({required CloudBackupJob job}) : _job = job;

  final CloudBackupJob _job;
  Timer? _timer;

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  void reschedule(ProfessionalBackupSettings settings) {
    dispose();

    if (!settings.cloudBackupEnabled) {
      return;
    }

    final now = DateTime.now();
    final next = _nextOccurrence(
      now,
      hour: settings.cloudBackupHour,
      minute: settings.cloudBackupMinute,
    );

    final delay = next.difference(now);
    _timer = Timer(delay, () async {
      try {
        await _job();
      } catch (_) {
        // Best-effort: scheduled backups must never crash the app.
      } finally {
        // Schedule again with current time; caller will typically re-reschedule
        // on settings changes, but this keeps it running.
        reschedule(settings);
      }
    });
  }

  static DateTime _nextOccurrence(
    DateTime now, {
    required int hour,
    required int minute,
  }) {
    final today = DateTime(now.year, now.month, now.day, hour, minute);
    if (now.isBefore(today)) {
      return today;
    }
    final tomorrow = today.add(const Duration(days: 1));
    return tomorrow;
  }
}
