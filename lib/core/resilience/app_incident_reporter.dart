import 'package:flutter/foundation.dart';

import 'app_incident.dart';
import 'benign_runtime_errors.dart';
import 'friendly_error_messages.dart';
import 'global_error_controller.dart';
import 'incident_logger.dart';

class AppIncidentReporter {
  AppIncidentReporter._();

  static final AppIncidentReporter instance = AppIncidentReporter._();

  IncidentLogger? _incidentLogger;
  GlobalErrorController? _errorController;

  void configure(
    IncidentLogger incidentLogger, {
    GlobalErrorController? errorController,
  }) {
    _incidentLogger = incidentLogger;
    _errorController = errorController;
  }

  Future<void> reportHandledOperation({
    required String action,
    String? module,
    required String title,
    required String message,
    required String details,
    required List<String> suggestions,
    required Object error,
    StackTrace? stackTrace,
    AppIncidentSeverity severity = AppIncidentSeverity.error,
    AppIncidentType type = AppIncidentType.operationFailed,
    bool presentToUser = true,
    AsyncIncidentAction? onRetry,
    AsyncIncidentAction? onRepair,
    VoidCallback? onContinue,
    VoidCallback? onGoBack,
    VoidCallback? onGoHome,
    bool canContinue = true,
    bool canGoBack = true,
    bool canGoHome = true,
    bool allowRepair = false,
    Map<String, Object?> extra = const {},
  }) async {
    if (BenignRuntimeErrors.shouldSuppress(error)) {
      return;
    }

    final incidentLogger = _incidentLogger;
    if (incidentLogger == null) {
      return;
    }

    final code = await incidentLogger.logMessageIncident(
      category: 'handled_operation',
      severity: severity,
      title: title,
      message: message,
      details: details,
      suggestions: suggestions,
      error: error,
      stackTrace: stackTrace,
      module: module,
      action: action,
      incidentType: type.name,
      extra: {'action': action, ...extra},
    );

    if (!presentToUser) {
      return;
    }

    final errorController = _errorController;
    if (errorController == null) {
      return;
    }

    errorController.presentLoggedIncident(
      code: code,
      category: 'handled_operation',
      type: type,
      severity: severity,
      friendlyMessage: FriendlyErrorMessage(
        title: title,
        message: message,
        details: details,
        suggestions: suggestions,
      ),
      error: error,
      stackTrace: stackTrace,
      module: module,
      action: action,
      onRetry: onRetry,
      onRepair: onRepair,
      onContinue: onContinue,
      onGoBack: onGoBack,
      onGoHome: onGoHome,
      canContinue: canContinue,
      canGoBack: canGoBack,
      canGoHome: canGoHome,
      allowRepair: allowRepair,
    );
  }
}
