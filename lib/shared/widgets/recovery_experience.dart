import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/resilience/app_incident.dart';
import '../../core/resilience/global_error_controller.dart';
import '../../core/resilience/startup_recovery_service.dart';

class StartupProgressScreen extends StatelessWidget {
  const StartupProgressScreen({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _RecoveryScaffold(
      accentColor: const Color(0xFF1E88E5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(strokeWidth: 3.5),
          ),
          const SizedBox(height: 24),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class StartupRecoveryPage extends StatefulWidget {
  const StartupRecoveryPage({
    super.key,
    required this.report,
    required this.onRetryStart,
    required this.onRetryRepair,
    this.onContinue,
    this.onRestoreBackup,
  });

  final StartupRecoveryReport report;
  final Future<void> Function() onRetryStart;
  final Future<void> Function() onRetryRepair;
  final VoidCallback? onContinue;
  final Future<String?> Function()? onRestoreBackup;

  @override
  State<StartupRecoveryPage> createState() => _StartupRecoveryPageState();
}

class _StartupRecoveryPageState extends State<StartupRecoveryPage> {
  String? _busyAction;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;

    return _RecoveryScaffold(
      accentColor: report.canContinue
          ? const Color(0xFFCF8B17)
          : const Color(0xFFB3261E),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(report.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(report.message, style: Theme.of(context).textTheme.bodyLarge),
          if (report.repairs.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Acciones realizadas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            ...report.repairs.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _BulletLine(text: item),
              ),
            ),
          ],
          if (report.suggestions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Sugerencias', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ...report.suggestions.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _BulletLine(text: item),
              ),
            ),
          ],
          if (report.incidentCode != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF2E7D4),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Incidente ${report.incidentCode}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _busyAction == null ? _retryStart : null,
                icon: const Icon(Icons.refresh),
                label: Text(
                  _busyAction == 'start'
                      ? 'Reintentando...'
                      : 'Reintentar inicio',
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _busyAction == null ? _retryRepair : null,
                icon: const Icon(Icons.build_circle_outlined),
                label: Text(
                  _busyAction == 'repair'
                      ? 'Reparando...'
                      : 'Intentar reparación automática',
                ),
              ),
              if (widget.onContinue != null)
                OutlinedButton.icon(
                  onPressed: _busyAction == null ? widget.onContinue : null,
                  icon: const Icon(Icons.arrow_forward_outlined),
                  label: const Text('Continuar en modo seguro'),
                ),
              if (widget.onRestoreBackup != null)
                OutlinedButton.icon(
                  onPressed: _busyAction == null ? _restoreBackup : null,
                  icon: const Icon(Icons.restore_outlined),
                  label: Text(
                    _busyAction == 'restore'
                        ? 'Restaurando...'
                        : 'Usar copia de seguridad (último recurso)',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _retryStart() async {
    setState(() => _busyAction = 'start');
    await widget.onRetryStart();
    if (mounted) {
      setState(() => _busyAction = null);
    }
  }

  Future<void> _retryRepair() async {
    setState(() => _busyAction = 'repair');
    await widget.onRetryRepair();
    if (mounted) {
      setState(() => _busyAction = null);
    }
  }

  Future<void> _restoreBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Restaurar copia de seguridad'),
          content: const Text(
            'Esta es la última medida disponible. La restauración puede reemplazar datos recientes. Si todavía es posible, el sistema creará primero una copia del estado actual.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Restaurar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || widget.onRestoreBackup == null) {
      return;
    }

    setState(() => _busyAction = 'restore');
    final failureMessage = await widget.onRestoreBackup!.call();
    if (!mounted) {
      return;
    }

    setState(() => _busyAction = null);
    if (failureMessage != null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }
}

class GlobalErrorOverlay extends StatelessWidget {
  const GlobalErrorOverlay({
    super.key,
    required this.controller,
    required this.child,
  });

  final GlobalErrorController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final incident = controller.activeIncident;

        return Stack(
          children: [
            child,
            if (incident != null)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.07),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: CompactGlobalErrorDialog(
                        userMessage: _buildCompactMessage(incident),
                        technicalDetails: incident.technicalDetails,
                        technicalStackTrace: incident.technicalStackTrace,
                        moduleName: incident.module,
                        incidentCode: incident.code,
                        occurredAt: incident.occurredAt,
                        onRetry: incident.canRetry ? controller.retry : null,
                        onClose: controller.clear,
                        onGoBack: incident.canGoBack ? controller.goBack : null,
                        onGoHome: incident.canGoHome ? controller.goHome : null,
                        canReport: false,
                        onReport: null,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class InlineRecoveryCard extends StatelessWidget {
  const InlineRecoveryCard({
    super.key,
    required this.title,
    required this.message,
    this.details = '',
    required this.suggestions,
  });

  final String title;
  final String message;
  final String details;
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            blurRadius: 32,
            offset: Offset(0, 18),
            color: Color(0x22000000),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(message),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                details,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF5E5A52),
                ),
              ),
            ],
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...suggestions.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _BulletLine(text: item),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class InlineModuleRecoveryCard extends StatelessWidget {
  const InlineModuleRecoveryCard({
    super.key,
    required this.title,
    required this.message,
    required this.details,
    required this.suggestions,
    required this.onRetry,
    this.onGoHome,
  });

  final String title;
  final String message;
  final String details;
  final List<String> suggestions;
  final VoidCallback onRetry;
  final VoidCallback? onGoHome;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF7F2E7), Color(0xFFFFFFFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                blurRadius: 30,
                offset: Offset(0, 18),
                color: Color(0x18000000),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFB3261E).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: Color(0xFFB3261E),
                  ),
                ),
                const SizedBox(height: 18),
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 10),
                Text(message, style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 10),
                Text(
                  details,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5E5A52),
                  ),
                ),
                if (suggestions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  ...suggestions.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _BulletLine(text: item),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                    if (onGoHome != null)
                      OutlinedButton.icon(
                        onPressed: onGoHome,
                        icon: const Icon(Icons.home_outlined),
                        label: const Text('Ir al inicio'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CompactGlobalErrorDialog extends StatelessWidget {
  const CompactGlobalErrorDialog({
    super.key,
    required this.userMessage,
    required this.onClose,
    this.technicalDetails,
    this.technicalStackTrace,
    this.onRetry,
    this.canReport = false,
    this.onReport,
    this.moduleName,
    this.screenName,
    this.connectionStatus,
    this.syncStatus,
    this.currentUser,
    this.onGoHome,
    this.onGoBack,
    this.incidentCode,
    this.occurredAt,
  });

  final String userMessage;
  final String? technicalDetails;
  final String? technicalStackTrace;
  final Future<void> Function()? onRetry;
  final VoidCallback onClose;
  final bool canReport;
  final Future<void> Function()? onReport;
  final String? moduleName;
  final String? screenName;
  final String? connectionStatus;
  final String? syncStatus;
  final String? currentUser;
  final VoidCallback? onGoHome;
  final VoidCallback? onGoBack;
  final String? incidentCode;
  final DateTime? occurredAt;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 700;
    final dialogWidth = isMobile
        ? screenWidth * 0.85
        : screenWidth.clamp(360.0, 420.0);

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogWidth.toDouble()),
        child: DecoratedBox(
          key: const Key('compact_error_card'),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                blurRadius: 18,
                offset: Offset(0, 8),
                color: Color(0x1A000000),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'No pudimos completar esta accion',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('compact_error_close_icon'),
                      visualDensity: VisualDensity.compact,
                      onPressed: onClose,
                      icon: const Icon(Icons.close, size: 18),
                      tooltip:
                          Overlay.maybeOf(context, rootOverlay: true) != null
                          ? 'Cerrar'
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  userMessage,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      key: const Key('compact_error_copy_button'),
                      onPressed: () => _copyReport(context),
                      child: const Text('Copiar error'),
                    ),
                    if (onRetry != null)
                      FilledButton.tonal(
                        key: const Key('compact_error_retry_button'),
                        onPressed: onRetry,
                        child: const Text('Reintentar'),
                      ),
                    if (onGoBack != null)
                      OutlinedButton(
                        key: const Key('compact_error_back_button'),
                        onPressed: onGoBack,
                        child: const Text('Volver'),
                      ),
                    if (onGoHome != null)
                      OutlinedButton(
                        key: const Key('compact_error_home_button'),
                        onPressed: onGoHome,
                        child: const Text('Ir al inicio'),
                      ),
                    if (canReport && onReport != null)
                      OutlinedButton(
                        key: const Key('compact_error_report_button'),
                        onPressed: onReport,
                        child: const Text('Reportar'),
                      ),
                    OutlinedButton(
                      key: const Key('compact_error_close_button'),
                      onPressed: onClose,
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyReport(BuildContext context) async {
    final buffer = StringBuffer()
      ..writeln('APP ERROR REPORT')
      ..writeln('Fecha: ${_safeValue(_formatDate(occurredAt))}')
      ..writeln('Modulo: ${_safeValue(moduleName)}')
      ..writeln('Usuario: ${_safeValue(currentUser)}')
      ..writeln('Pantalla: ${_safeValue(screenName)}')
      ..writeln('Conexion: ${_safeValue(connectionStatus)}')
      ..writeln('Sync status: ${_safeValue(syncStatus)}')
      ..writeln('Incidente: ${_safeValue(incidentCode)}')
      ..writeln('Mensaje usuario: ${_safeValue(userMessage)}')
      ..writeln('Mensaje tecnico: ${_sanitizeTechnical(technicalDetails)}')
      ..writeln('Stacktrace: ${_sanitizeTechnical(technicalStackTrace)}');

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('Detalle copiado.')));
  }

  String _sanitizeTechnical(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return 'No disponible';
    }

    return text
        .replaceAll(
          RegExp(
            r'authorization\s*:\s*bearer\s+[^\s,;]+',
            caseSensitive: false,
          ),
          'Authorization: Bearer [REDACTED]',
        )
        .replaceAll(
          RegExp(r'authorization\s*:\s*[^\s,;]+', caseSensitive: false),
          'Authorization: [REDACTED]',
        )
        .replaceAll(
          RegExp(r'bearer\s+[a-z0-9\-._~+/]+=*', caseSensitive: false),
          'Bearer [REDACTED]',
        )
        .replaceAll(
          RegExp(r'jwt\s*[:=]\s*[^\s,;]+', caseSensitive: false),
          'jwt=[REDACTED]',
        )
        .replaceAll(
          RegExp(
            r'(token|password|contrasena)\s*[:=]\s*[^\s,;]+',
            caseSensitive: false,
          ),
          'credential=[REDACTED]',
        );
  }

  String _safeValue(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return 'No disponible';
    }
    return normalized;
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '';
    }
    return value.toIso8601String();
  }
}

String _buildCompactMessage(AppIncident incident) {
  final combined =
      '${incident.message} ${incident.details} ${incident.technicalDetails ?? ''}'
          .toLowerCase();
  if (_looksOfflineOrServerIssue(combined)) {
    return 'No hay conexion en este momento. Puedes seguir trabajando y la app sincronizara luego.';
  }

  if (combined.contains('permiso') ||
      combined.contains('forbidden') ||
      combined.contains('unauthorized')) {
    return 'No tienes permiso para realizar esta accion.';
  }

  if (combined.contains('invalid') ||
      combined.contains('validation') ||
      combined.contains('campo')) {
    return 'Revisa los datos ingresados e intentalo nuevamente.';
  }

  if (combined.contains('database') || combined.contains('sqlite')) {
    return 'Hubo un problema guardando la informacion local. Cierra y abre la app si continua.';
  }

  return 'La app sigue funcionando. Puedes intentarlo otra vez.';
}

bool _looksOfflineOrServerIssue(String value) {
  return value.contains('socket') ||
      value.contains('offline') ||
      value.contains('sin conexion') ||
      value.contains('failed host lookup') ||
      value.contains('backend') ||
      value.contains('servidor') ||
      value.contains('server') ||
      value.contains('statuscode') ||
      value.contains('status code');
}

class _RecoveryScaffold extends StatelessWidget {
  const _RecoveryScaffold({required this.child, required this.accentColor});

  final Widget child;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFF4EFE4),
              accentColor.withValues(alpha: 0.10),
              const Color(0xFFFFFFFF),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 780),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: const [
                          BoxShadow(
                            blurRadius: 36,
                            offset: Offset(0, 24),
                            color: Color(0x1A000000),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BulletLine extends StatelessWidget {
  const _BulletLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8),
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF1E88E5),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }
}
