import 'package:flutter/material.dart';

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
                  color: Colors.black.withValues(alpha: 0.38),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Material(
                          color: Colors.transparent,
                          child: _IncidentPanel(
                            incident: incident,
                            onRetry: incident.canRetry
                                ? controller.retry
                                : null,
                            onRepair: incident.allowRepair
                                ? controller.repair
                                : null,
                            onContinue: incident.canContinue
                                ? controller.continueWorking
                                : null,
                            onBack: incident.canGoBack
                                ? controller.goBack
                                : null,
                            onHome: incident.canGoHome
                              ? controller.goHome
                              : null,
                          ),
                        ),
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

class _IncidentPanel extends StatelessWidget {
  const _IncidentPanel({
    required this.incident,
    this.onRetry,
    this.onRepair,
    this.onContinue,
    this.onBack,
    this.onHome,
  });

  final AppIncident incident;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onRepair;
  final VoidCallback? onContinue;
  final VoidCallback? onBack;
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    final accent = _accentForIncident(incident);
    final badgeLabel = _badgeLabel(incident);
    final icon = _iconForIncident(incident);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF6F2E8), Color(0xFFFFFFFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            blurRadius: 36,
            offset: Offset(0, 24),
            color: Color(0x28000000),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badgeLabel,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(height: 18),
            Text(
              incident.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              incident.message,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 10),
            Text(
              incident.details,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF5E5A52),
              ),
            ),
            if (incident.suggestions.isNotEmpty) ...[
              const SizedBox(height: 18),
              ...incident.suggestions.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _BulletLine(text: item),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              'Incidente ${incident.code}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (onRetry != null)
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                if (onBack != null)
                  OutlinedButton.icon(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_outlined),
                    label: const Text('Volver atras'),
                  ),
                if (onHome != null)
                  OutlinedButton.icon(
                    onPressed: onHome,
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Ir al inicio'),
                  ),
                if (onRepair != null)
                  FilledButton.tonalIcon(
                    onPressed: onRepair,
                    icon: const Icon(Icons.build_outlined),
                    label: const Text('Reparar'),
                  ),
                if (onContinue != null)
                  OutlinedButton.icon(
                    onPressed: onContinue,
                    icon: const Icon(Icons.play_arrow_outlined),
                    label: Text(
                      incident.type == AppIncidentType.recoverable
                          ? 'Seguir trabajando'
                          : 'Continuar',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Color _accentForIncident(AppIncident incident) {
  return switch (incident.type) {
    AppIncidentType.recoverable => const Color(0xFFCF8B17),
    AppIncidentType.operationFailed => const Color(0xFFB3261E),
    AppIncidentType.criticalRecovery => const Color(0xFF8E1B13),
    AppIncidentType.startup => const Color(0xFF1E5DB0),
  };
}

String _badgeLabel(AppIncident incident) {
  return switch (incident.type) {
    AppIncidentType.recoverable => 'Error recuperable',
    AppIncidentType.operationFailed => 'Operacion no completada',
    AppIncidentType.criticalRecovery => 'Recuperacion guiada',
    AppIncidentType.startup => 'Inicio del sistema',
  };
}

IconData _iconForIncident(AppIncident incident) {
  return switch (incident.type) {
    AppIncidentType.recoverable => Icons.warning_amber_rounded,
    AppIncidentType.operationFailed => Icons.report_problem_outlined,
    AppIncidentType.criticalRecovery => Icons.health_and_safety_outlined,
    AppIncidentType.startup => Icons.rocket_launch_outlined,
  };
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
