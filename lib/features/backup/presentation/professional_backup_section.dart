import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/system/system_config_service.dart';
import '../../../services/professional_backup/backup_service.dart' as professional;
import '../../../services/professional_backup/professional_backup_settings.dart';

class ProfessionalBackupSection extends StatefulWidget {
  const ProfessionalBackupSection({
    super.key,
    required this.ensureAuthorized,
  });

  final Future<bool> Function() ensureAuthorized;

  @override
  State<ProfessionalBackupSection> createState() =>
      _ProfessionalBackupSectionState();
}

class _ProfessionalBackupSectionState extends State<ProfessionalBackupSection> {
  final professional.BackupService _backupService =
      professional.BackupService.instance;

  ProfessionalBackupSettings? _settings;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final settings = await _backupService.getSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _save(ProfessionalBackupSettings next) async {
    setState(() {
      _busy = true;
      _error = null;
      _settings = next;
    });

    try {
      final allowed = await widget.ensureAuthorized();
      if (!allowed) {
        if (!mounted) return;
        setState(() {
          _busy = false;
        });
        return;
      }

      await _backupService.saveSettings(next);
      if (!mounted) return;
      setState(() {
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _runManualBackup() async {
    final allowed = await widget.ensureAuthorized();
    if (!allowed || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final file = await _backupService.createLocalBackup(
        trigger: professional.BackupTrigger.manual,
      );
      if (!mounted) return;

      setState(() {
        _busy = false;
      });

      final message = file == null
          ? 'Backup local deshabilitado.'
          : 'Backup creado: ${file.path}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _pickTime(ProfessionalBackupSettings current) async {
    final allowed = await widget.ensureAuthorized();
    if (!allowed || !mounted) {
      return;
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: current.cloudBackupHour,
        minute: current.cloudBackupMinute,
      ),
    );

    if (picked == null) {
      return;
    }

    await _save(
      current.copyWith(
        cloudBackupHour: picked.hour,
        cloudBackupMinute: picked.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Backup profesional',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Backup local persistente + backup diario en la nube (rotativo 4 días).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.red.shade700),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Backup local (automático)'),
              subtitle: const Text('Guarda copias en /backups/local/ (15 últimas).'),
              value: settings?.localBackupEnabled ?? true,
              onChanged: settings == null || _busy
                  ? null
                  : (value) => _save(settings.copyWith(localBackupEnabled: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Backup en la nube (diario)'),
              subtitle: const Text('Sube un ZIP de la DB al backend.'),
              value: settings?.cloudBackupEnabled ?? false,
              onChanged: settings == null || _busy
                  ? null
                  : (value) =>
                      _save(settings.copyWith(cloudBackupEnabled: value)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hora del backup nube'),
              subtitle: Text(settings?.cloudBackupTimeLabel ?? '02:00'),
              trailing: TextButton(
                onPressed: settings == null || _busy
                    ? null
                    : () => _pickTime(settings),
                child: const Text('Cambiar'),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _busy ? null : _runManualBackup,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Crear backup manual'),
                ),
                const SizedBox(width: 12),
                if (SystemConfigService.instance.isReadOnly)
                  Text(
                    'Modo solo lectura',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
