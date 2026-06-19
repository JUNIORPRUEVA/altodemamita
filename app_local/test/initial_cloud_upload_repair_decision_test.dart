import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_solares/services/sync/sync_config_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'nube vacia fuerza InitialCloudUpload aunque exista bandera vieja completed',
    () async {
      SharedPreferences.setMockInitialValues({
        SyncConfigRepository.syncLocalUploadBootstrapCompletedKey: true,
        SyncConfigRepository.syncLocalUploadBootstrapBackendUrlKey:
            'https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api',
        SyncConfigRepository.syncLocalUploadBootstrapDatabaseNameKey:
            'altodemamita_anterior',
        SyncConfigRepository.syncLocalUploadBootstrapCloudFingerprintKey:
            'fingerprint-anterior',
      });
      final repository = SyncConfigRepository(
        preferencesFactory: SharedPreferences.getInstance,
      );

      final diagnostics = await repository.loadLocalUploadBootstrapDiagnostics(
        backendUrl:
            'https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api',
        cloudIdentity: const CloudIdentity(
          databaseName: 'altodemamita_nueva',
          databaseHost: 'altomamita-postgres:5432',
          cloudFingerprint: 'fingerprint-nueva',
          initialUploadRequired: true,
          cloudData: CloudData(
            clients: 0,
            sellers: 0,
            lots: 0,
            sales: 0,
            installments: 0,
            payments: 0,
            syncBatches: 0,
          ),
        ),
      );

      expect(diagnostics.completedFlag, isTrue);
      expect(diagnostics.shouldRun, isTrue);
      expect(diagnostics.reason, 'backend_initial_upload_required');
    },
  );

  test(
    'completed viejo sin identidad de nube no bloquea InitialCloudUpload',
    () async {
      SharedPreferences.setMockInitialValues({
        SyncConfigRepository.syncLocalUploadBootstrapCompletedKey: true,
        SyncConfigRepository.syncLocalUploadBootstrapBackendUrlKey:
            'https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api',
      });
      final repository = SyncConfigRepository(
        preferencesFactory: SharedPreferences.getInstance,
      );

      final diagnostics = await repository.loadLocalUploadBootstrapDiagnostics(
        backendUrl:
            'https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api',
        cloudIdentity: const CloudIdentity(
          databaseName: 'altodemamita_oficial',
          databaseHost: 'altomamita-postgres:5432',
          cloudFingerprint: 'fingerprint-oficial',
          initialUploadRequired: false,
          cloudData: CloudData(
            clients: 6,
            sellers: 3,
            lots: 13,
            sales: 4,
            installments: 48,
            payments: 4,
            syncBatches: 1,
          ),
        ),
      );

      expect(diagnostics.shouldRun, isTrue);
      expect(diagnostics.reason, 'old_completed_without_cloud_identity');
    },
  );

  test(
    'misma URL con databaseName diferente vuelve a correr InitialCloudUpload',
    () async {
      SharedPreferences.setMockInitialValues({
        SyncConfigRepository.syncLocalUploadBootstrapCompletedKey: true,
        SyncConfigRepository.syncLocalUploadBootstrapBackendUrlKey:
            'https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api',
        SyncConfigRepository.syncLocalUploadBootstrapDatabaseNameKey:
            'altodemamita_a',
        SyncConfigRepository.syncLocalUploadBootstrapDatabaseHostKey:
            'altomamita-postgres:5432',
        SyncConfigRepository.syncLocalUploadBootstrapCloudFingerprintKey:
            'fingerprint-a',
      });
      final repository = SyncConfigRepository(
        preferencesFactory: SharedPreferences.getInstance,
      );

      final diagnostics = await repository.loadLocalUploadBootstrapDiagnostics(
        backendUrl:
            'https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api',
        cloudIdentity: const CloudIdentity(
          databaseName: 'altodemamita_b',
          databaseHost: 'altomamita-postgres:5432',
          cloudFingerprint: 'fingerprint-b',
          initialUploadRequired: false,
          cloudData: CloudData(
            clients: 6,
            sellers: 3,
            lots: 13,
            sales: 4,
            installments: 48,
            payments: 4,
            syncBatches: 1,
          ),
        ),
      );

      expect(diagnostics.shouldRun, isTrue);
      expect(diagnostics.reason, 'database_name_changed');
    },
  );

  test('misma nube con datos no repite InitialCloudUpload', () async {
    SharedPreferences.setMockInitialValues({
      SyncConfigRepository.syncLocalUploadBootstrapCompletedKey: true,
      SyncConfigRepository.syncLocalUploadBootstrapBackendUrlKey:
          'https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api',
      SyncConfigRepository.syncLocalUploadBootstrapDatabaseNameKey:
          'altodemamita_oficial',
      SyncConfigRepository.syncLocalUploadBootstrapDatabaseHostKey:
          'altomamita-postgres:5432',
      SyncConfigRepository.syncLocalUploadBootstrapCloudFingerprintKey:
          'fingerprint-oficial',
    });
    final repository = SyncConfigRepository(
      preferencesFactory: SharedPreferences.getInstance,
    );

    final diagnostics = await repository.loadLocalUploadBootstrapDiagnostics(
      backendUrl:
          'https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api',
      cloudIdentity: const CloudIdentity(
        databaseName: 'altodemamita_oficial',
        databaseHost: 'altomamita-postgres:5432',
        cloudFingerprint: 'fingerprint-oficial',
        initialUploadRequired: false,
        cloudData: CloudData(
          clients: 6,
          sellers: 3,
          lots: 13,
          sales: 4,
          installments: 48,
          payments: 4,
          syncBatches: 1,
        ),
      ),
    );

    expect(diagnostics.shouldRun, isFalse);
    expect(diagnostics.reason, 'already_completed_same_cloud');
  });
}
