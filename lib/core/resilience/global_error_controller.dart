import 'package:flutter/material.dart';

import 'app_incident.dart';
import 'benign_runtime_errors.dart';
import 'friendly_error_messages.dart';
import 'incident_logger.dart';

class GlobalErrorController extends ChangeNotifier {
  GlobalErrorController({required IncidentLogger incidentLogger})
    : _incidentLogger = incidentLogger;

  final IncidentLogger _incidentLogger;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  AppIncident? _activeIncident;

  AppIncident? get activeIncident => _activeIncident;
  bool get hasActiveIncident => _activeIncident != null;

  Future<void> reportUnexpected({
    required Object error,
    StackTrace? stackTrace,
    String category = 'unexpected',
    String? module,
    String? action,
    FriendlyErrorMessage? friendlyMessage,
    AppIncidentType type = AppIncidentType.criticalRecovery,
    AppIncidentSeverity severity = AppIncidentSeverity.error,
    AsyncIncidentAction? onRetry,
    AsyncIncidentAction? onRepair,
    VoidCallback? onContinue,
    VoidCallback? onGoBack,
    VoidCallback? onGoHome,
    bool canContinue = true,
    bool canGoBack = true,
    bool canGoHome = false,
    bool allowRepair = false,
  }) async {
    if (BenignRuntimeErrors.shouldSuppress(error)) {
      return;
    }

    final resolved = friendlyMessage ?? FriendlyErrorMessages.unexpected(error);
    final code = await _incidentLogger.logIncident(
      category: category,
      severity: severity,
      friendlyMessage: resolved,
      error: error,
      stackTrace: stackTrace,
      module: module,
      action: action,
      incidentType: type.name,
    );

    presentLoggedIncident(
      code: code,
      category: category,
      type: type,
      severity: severity,
      friendlyMessage: resolved,
      module: module,
      action: action,
      error: error,
      stackTrace: stackTrace,
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

  void presentLoggedIncident({
    required String code,
    required String category,
    required AppIncidentType type,
    required AppIncidentSeverity severity,
    required FriendlyErrorMessage friendlyMessage,
    Object? error,
    StackTrace? stackTrace,
    String? module,
    String? action,
    AsyncIncidentAction? onRetry,
    AsyncIncidentAction? onRepair,
    VoidCallback? onContinue,
    VoidCallback? onGoBack,
    VoidCallback? onGoHome,
    bool canContinue = true,
    bool canGoBack = true,
    bool canGoHome = false,
    bool allowRepair = false,
  }) {
    _activeIncident = AppIncident(
      code: code,
      title: friendlyMessage.title,
      message: friendlyMessage.message,
      details: friendlyMessage.details,
      suggestions: friendlyMessage.suggestions,
      category: category,
      type: type,
      severity: severity,
      occurredAt: DateTime.now(),
      module: module,
      action: action,
      technicalDetails: error.toString(),
      technicalStackTrace: stackTrace?.toString(),
      canRetry: onRetry != null,
      canGoBack: canGoBack,
      canContinue: canContinue,
      canGoHome: canGoHome,
      allowRepair: allowRepair,
      onRetry: onRetry,
      onRepair: onRepair,
      onContinue: onContinue,
      onGoBack: onGoBack,
      onGoHome: onGoHome,
    );
    notifyListeners();
  }

  Future<void> retry() async {
    final action = _activeIncident?.onRetry;
    clear();
    if (action != null) {
      await action();
    }
  }

  Future<void> repair() async {
    final action = _activeIncident?.onRepair;
    clear();
    if (action != null) {
      await action();
    }
  }

  void continueWorking() {
    final action = _activeIncident?.onContinue;
    clear();
    action?.call();
  }

  void goBack() {
    final action = _activeIncident?.onGoBack;
    clear();

    if (action != null) {
      action();
      return;
    }

    navigatorKey.currentState?.maybePop();
  }

  void goHome() {
    final action = _activeIncident?.onGoHome;
    clear();

    if (action != null) {
      action();
      return;
    }

    navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  void clear() {
    _activeIncident = null;
    notifyListeners();
  }
}
