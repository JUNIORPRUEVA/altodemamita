import 'dart:async';

import 'package:flutter/material.dart';

enum AppIncidentSeverity { warning, error, critical }

enum AppIncidentType { recoverable, operationFailed, criticalRecovery, startup }

typedef AsyncIncidentAction = Future<void> Function();

class AppIncident {
  const AppIncident({
    required this.code,
    required this.title,
    required this.message,
    required this.details,
    required this.suggestions,
    required this.category,
    required this.type,
    required this.severity,
    required this.occurredAt,
    this.module,
    this.action,
    this.technicalDetails,
    this.technicalStackTrace,
    this.canRetry = true,
    this.canGoBack = true,
    this.canContinue = true,
    this.canGoHome = false,
    this.allowRepair = false,
    this.allowBackupRestore = false,
    this.onRetry,
    this.onRepair,
    this.onContinue,
    this.onGoBack,
    this.onGoHome,
  });

  final String code;
  final String title;
  final String message;
  final String details;
  final List<String> suggestions;
  final String category;
  final AppIncidentType type;
  final AppIncidentSeverity severity;
  final DateTime occurredAt;
  final String? module;
  final String? action;
  final String? technicalDetails;
  final String? technicalStackTrace;
  final bool canRetry;
  final bool canGoBack;
  final bool canContinue;
  final bool canGoHome;
  final bool allowRepair;
  final bool allowBackupRestore;
  final AsyncIncidentAction? onRetry;
  final AsyncIncidentAction? onRepair;
  final VoidCallback? onContinue;
  final VoidCallback? onGoBack;
  final VoidCallback? onGoHome;
}
