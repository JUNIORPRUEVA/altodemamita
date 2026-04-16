import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/resilience/app_incident.dart';
import 'package:sistema_solares/core/resilience/app_incident_reporter.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';
import 'package:sistema_solares/core/resilience/friendly_error_messages.dart';
import 'package:sistema_solares/core/resilience/global_error_controller.dart';
import 'package:sistema_solares/core/resilience/incident_logger.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'sistema_solares_global_error_',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'reportHandledOperation shows only friendly content and persists technical detail',
    () async {
      final appPaths = AppPaths(supportDirectory: tempDirectory.path);
      final logger = IncidentLogger(appPaths: appPaths);
      final controller = GlobalErrorController(incidentLogger: logger);
      final rawError = StateError('sqlite failure on clientes table');
      final friendly = FriendlyErrorMessages.operation(
        action: 'guardar el cliente',
        module: 'clientes',
        error: rawError,
      );

      AppIncidentReporter.instance.configure(
        logger,
        errorController: controller,
      );

      await AppIncidentReporter.instance.reportHandledOperation(
        action: 'guardar el cliente',
        module: 'clientes',
        title: friendly.title,
        message: friendly.message,
        details: friendly.details,
        suggestions: friendly.suggestions,
        error: rawError,
        type: AppIncidentType.operationFailed,
      );

      final incident = controller.activeIncident;
      expect(incident, isNotNull);
      expect(incident!.type, AppIncidentType.operationFailed);
      expect(incident.module, 'clientes');
      expect(incident.action, 'guardar el cliente');
      expect(incident.title, friendly.title);
      expect(incident.message, friendly.message);
      expect(incident.details, friendly.details);
      expect(incident.message.contains('sqlite'), isFalse);
      expect(incident.details.contains('sqlite'), isFalse);
      expect(incident.technicalDetails, contains('sqlite failure'));

      final files = await Directory(appPaths.incidentsDirectory)
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();

      expect(files, hasLength(1));

      final lines = await files.single.readAsLines();
      final payload = jsonDecode(lines.single) as Map<String, Object?>;

      expect(payload['module'], 'clientes');
      expect(payload['action'], 'guardar el cliente');
      expect(payload['type'], AppIncidentType.operationFailed.name);
      expect(payload['message'], friendly.message);
      expect(payload['details'], friendly.details);
      expect(payload['error'], contains('sqlite failure on clientes table'));
    },
  );

  test(
    'reportUnexpected keeps technical path out of the visible incident and logs module context',
    () async {
      final appPaths = AppPaths(supportDirectory: tempDirectory.path);
      final logger = IncidentLogger(appPaths: appPaths);
      final controller = GlobalErrorController(incidentLogger: logger);
      final rawError = FileSystemException(
        'disk full',
        r'C:\secret\sistema_solares\db.sqlite',
      );

      await controller.reportUnexpected(
        error: rawError,
        category: 'backup_unexpected',
        module: 'backup',
        action: 'crear la copia de seguridad',
        canGoHome: true,
      );

      final incident = controller.activeIncident;
      expect(incident, isNotNull);
      expect(incident!.code, startsWith('INC-'));
      expect(incident.type, AppIncidentType.criticalRecovery);
      expect(incident.module, 'backup');
      expect(incident.action, 'crear la copia de seguridad');
      expect(incident.canGoHome, isTrue);
      expect(incident.message.contains(r'C:\secret'), isFalse);
      expect(incident.details.contains(r'C:\secret'), isFalse);
      expect(incident.technicalDetails, contains(r'C:\secret\sistema_solares\db.sqlite'));

      final files = await Directory(appPaths.incidentsDirectory)
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();

      expect(files, hasLength(1));

      final payload = jsonDecode((await files.single.readAsLines()).single)
          as Map<String, Object?>;

      expect(payload['module'], 'backup');
      expect(payload['action'], 'crear la copia de seguridad');
      expect(payload['type'], AppIncidentType.criticalRecovery.name);
      expect(payload['error'], contains(r'C:\secret\sistema_solares\db.sqlite'));
    },
  );
}