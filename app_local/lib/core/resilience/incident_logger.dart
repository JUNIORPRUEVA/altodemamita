import 'dart:convert';
import 'dart:io';

import 'app_incident.dart';
import 'app_paths.dart';
import 'friendly_error_messages.dart';

class IncidentLogger {
  IncidentLogger({AppPaths? appPaths}) : _appPaths = appPaths ?? AppPaths();

  final AppPaths _appPaths;

  Future<String> logIncident({
    required String category,
    required AppIncidentSeverity severity,
    required FriendlyErrorMessage friendlyMessage,
    Object? error,
    StackTrace? stackTrace,
    String? module,
    String? action,
    String? incidentType,
    Map<String, Object?> extra = const {},
  }) async {
    return logMessageIncident(
      category: category,
      severity: severity,
      title: friendlyMessage.title,
      message: friendlyMessage.message,
      details: friendlyMessage.details,
      suggestions: friendlyMessage.suggestions,
      error: error,
      stackTrace: stackTrace,
      module: module,
      action: action,
      incidentType: incidentType,
      extra: extra,
    );
  }

  Future<String> logMessageIncident({
    required String category,
    required AppIncidentSeverity severity,
    required String title,
    required String message,
    String? details,
    List<String> suggestions = const [],
    Object? error,
    StackTrace? stackTrace,
    String? module,
    String? action,
    String? incidentType,
    Map<String, Object?> extra = const {},
  }) async {
    await _appPaths.ensureCriticalDirectories();

    final now = DateTime.now();
    final code = _buildIncidentCode(now);
    final file = File(
      '${_appPaths.incidentsDirectory}${Platform.pathSeparator}${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.jsonl',
    );

    final payload = <String, Object?>{
      'code': code,
      'timestamp': now.toIso8601String(),
      'category': category,
      'type': incidentType,
      'severity': severity.name,
      'module': module,
      'action': action,
      'title': title,
      'message': message,
      'details': details,
      'suggestions': suggestions,
      'error': error?.toString(),
      'stackTrace': stackTrace?.toString(),
      'extra': extra,
    };

    await file.writeAsString('${jsonEncode(payload)}\n', mode: FileMode.append);
    return code;
  }

  String _buildIncidentCode(DateTime value) {
    final stamp =
        '${value.year.toString().padLeft(4, '0')}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}-${value.hour.toString().padLeft(2, '0')}${value.minute.toString().padLeft(2, '0')}${value.second.toString().padLeft(2, '0')}';
    final suffix = value.microsecondsSinceEpoch
        .remainder(100000)
        .toString()
        .padLeft(5, '0');
    return 'INC-$stamp-$suffix';
  }
}
