import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

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
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    final backupDirectory = _backupService.localBackupDirectoryPath;
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
          : 'Backup creado: ${path.basename(file.path)}';

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

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final backupDirectory = _backupService.localBackupDirectoryPath;

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
              'Backup local 100% offline. Sin nube ni sincronización remota.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SelectableText(
              'Destino: $backupDirectory',
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
              subtitle: const Text('Guarda copias SQLite locales y conserva las 15 más recientes.'),
              value: settings?.localBackupEnabled ?? true,
              onChanged: settings == null || _busy
                  ? null
                  : (value) => _save(settings.copyWith(localBackupEnabled: value)),
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
