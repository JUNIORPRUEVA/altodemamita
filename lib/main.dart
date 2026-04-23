import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/database/app_database.dart';
import 'core/resilience/app_incident.dart';
import 'core/resilience/app_incident_reporter.dart';
import 'core/resilience/app_paths.dart';
import 'core/resilience/friendly_error_messages.dart';
import 'core/resilience/global_error_controller.dart';
import 'core/resilience/incident_logger.dart';
import 'core/resilience/startup_recovery_service.dart';
import 'core/theme/app_theme.dart';
import 'features/backup/data/backup_config_repository.dart';
import 'features/backup/presentation/backup_lifecycle_observer.dart';
import 'features/backup/services/backup_service.dart';
import 'features/backup/services/disk_detection_service.dart';
import 'services/professional_backup/backup_service.dart' as professional_backup;
import 'services/professional_backup/professional_backup_lifecycle_observer.dart';
import 'shared/widgets/recovery_experience.dart';

Future<void> main() async {
  late final GlobalErrorController errorController;

  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      final appPaths = AppPaths();
      final backupConfigRepository = BackupConfigRepository();
      final incidentLogger = IncidentLogger(appPaths: appPaths);
      errorController = GlobalErrorController(incidentLogger: incidentLogger);
      AppIncidentReporter.instance.configure(
        incidentLogger,
        errorController: errorController,
      );
      final diskDetectionService = DiskDetectionService();
      final backupService = BackupService(
        appDatabase: AppDatabase.instance,
        configRepository: backupConfigRepository,
        diskDetectionService: diskDetectionService,
      );

      final professionalBackupService = professional_backup.BackupService.instance;
      final startupRecoveryService = StartupRecoveryService(
        appDatabase: AppDatabase.instance,
        backupConfigRepository: backupConfigRepository,
        backupService: backupService,
        diskDetectionService: diskDetectionService,
        incidentLogger: incidentLogger,
        appPaths: appPaths,
      );

      FlutterError.onError = (details) {
        if (kDebugMode) {
          FlutterError.presentError(details);
        }

        unawaited(
          errorController.reportUnexpected(
            error: details.exception,
            stackTrace: details.stack,
            category: 'flutter_framework',
            module: 'interfaz',
            action: 'renderizar la aplicacion',
            severity: AppIncidentSeverity.critical,
          ),
        );
      };

      ErrorWidget.builder = (details) {
        final friendly = FriendlyErrorMessages.unexpected(details.exception);
        return Material(
          color: Colors.transparent,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: InlineRecoveryCard(
                title: friendly.title,
                message: friendly.message,
                details: friendly.details,
                suggestions: friendly.suggestions,
              ),
            ),
          ),
        );
      };

      PlatformDispatcher.instance.onError = (error, stackTrace) {
        unawaited(
          errorController.reportUnexpected(
            error: error,
            stackTrace: stackTrace,
            category: 'platform_dispatcher',
            module: 'nucleo del sistema',
            action: 'procesar la aplicacion',
            severity: AppIncidentSeverity.critical,
          ),
        );
        return true;
      };

      runApp(
        SistemaSolaresBootstrap(
          startupRecoveryService: startupRecoveryService,
          backupService: backupService,
          professionalBackupService: professionalBackupService,
          errorController: errorController,
        ),
      );
    },
    (error, stackTrace) {
      unawaited(
        errorController.reportUnexpected(
          error: error,
          stackTrace: stackTrace,
          category: 'zone_guarded',
          module: 'nucleo del sistema',
          action: 'ejecutar la aplicacion',
          severity: AppIncidentSeverity.critical,
        ),
      );
    },
  );
}

class SistemaSolaresBootstrap extends StatefulWidget {
  const SistemaSolaresBootstrap({
    super.key,
    required this.startupRecoveryService,
    required this.backupService,
    required this.professionalBackupService,
    required this.errorController,
  });

  final StartupRecoveryService startupRecoveryService;
  final BackupService backupService;
  final professional_backup.BackupService professionalBackupService;
  final GlobalErrorController errorController;

  @override
  State<SistemaSolaresBootstrap> createState() =>
      _SistemaSolaresBootstrapState();
}

class _SistemaSolaresBootstrapState extends State<SistemaSolaresBootstrap> {
  Future<StartupRecoveryReport>? _startupFuture;
  String _startupStatus = 'Preparando sistema local...';
  bool _continueWithMinimalMode = false;
  BackupLifecycleObserver? _backupLifecycleObserver;
  ProfessionalBackupLifecycleObserver? _professionalBackupLifecycleObserver;

  @override
  void initState() {
    super.initState();
    _runStartup();
  }

  void _runStartup({bool aggressiveRepair = false}) {
    setState(() {
      _continueWithMinimalMode = false;
      _startupStatus = 'Preparando sistema local...';
      _startupFuture = widget.startupRecoveryService.prepareApplication(
        aggressiveRepair: aggressiveRepair,
        onStatus: (status) {
          if (!mounted) {
            return;
          }
          setState(() {
            _startupStatus = status;
          });
        },
      );
    });
  }

  Future<String?> _restoreLatestBackup() async {
    final report = await _startupFuture;
    final backupPath = report?.latestBackupPath;
    if (backupPath == null) {
      return 'No hay una copia disponible para restaurar en este equipo.';
    }

    final result = await widget.backupService.restoreFromBackup(
      backupPath: backupPath,
    );

    if (!mounted) {
      return null;
    }

    if (!result.success) {
      return 'No fue posible restaurar la copia seleccionada. Puede reintentar o seguir con la reparación automática.';
    }

    _runStartup(aggressiveRepair: true);
    return null;
  }

  @override
  void dispose() {
    final observer = _backupLifecycleObserver;
    if (observer != null) {
      WidgetsBinding.instance.removeObserver(observer);
    }
    final professionalObserver = _professionalBackupLifecycleObserver;
    if (professionalObserver != null) {
      WidgetsBinding.instance.removeObserver(professionalObserver);
    }
    widget.professionalBackupService.dispose();
    super.dispose();
  }

  void _registerBackupObserverIfNeeded() {
    if (_backupLifecycleObserver != null) {
      return;
    }

    final observer = BackupLifecycleObserver(backupService: widget.backupService);
    WidgetsBinding.instance.addObserver(observer);
    _backupLifecycleObserver = observer;
  }

  void _registerProfessionalBackupObserverIfNeeded() {
    if (_professionalBackupLifecycleObserver != null) {
      return;
    }

    unawaited(widget.professionalBackupService.initialize());
    final observer = ProfessionalBackupLifecycleObserver(
      backupService: widget.professionalBackupService,
    );
    WidgetsBinding.instance.addObserver(observer);
    _professionalBackupLifecycleObserver = observer;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StartupRecoveryReport>(
      future: _startupFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _standalone(
            StartupProgressScreen(
              title: 'Iniciando sistema',
              message: _startupStatus,
            ),
          );
        }

        final report = snapshot.data;
        if (report == null) {
          return _standalone(
            StartupRecoveryPage(
              report: const StartupRecoveryReport(
                status: StartupRecoveryStatus.failed,
                title: 'No se pudo completar el inicio',
                message:
                    'El sistema no pudo terminar de prepararse en este momento.',
                suggestions: [
                  'Use Reintentar inicio para volver a cargar.',
                  'Si no mejora, pruebe la reparación automática.',
                ],
                repairs: [],
                showRecoveryScreen: true,
                canContinue: false,
                allowBackupRestore: false,
              ),
              onRetryStart: () async => _runStartup(),
              onRetryRepair: () async => _runStartup(aggressiveRepair: true),
            ),
          );
        }

        if (report.showRecoveryScreen && !_continueWithMinimalMode) {
          return _standalone(
            StartupRecoveryPage(
              report: report,
              onRetryStart: () async => _runStartup(),
              onRetryRepair: () async => _runStartup(aggressiveRepair: true),
              onContinue: report.canContinue
                  ? () {
                      setState(() {
                        _continueWithMinimalMode = true;
                      });
                    }
                  : null,
              onRestoreBackup: report.allowBackupRestore
                  ? _restoreLatestBackup
                  : null,
            ),
          );
        }

        _registerBackupObserverIfNeeded();
        _registerProfessionalBackupObserverIfNeeded();

        return SistemaSolaresApp(errorController: widget.errorController);
      },
    );
  }

  Widget _standalone(Widget child) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: child,
    );
  }
}
