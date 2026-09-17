import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:sistema_solares/core/resilience/app_paths.dart';
import 'package:sistema_solares/core/resilience/app_storage_namespace.dart';

/// Aislamiento de almacenamiento local PROD vs UAT.
///
/// El requisito es estructural: el MISMO código, instalado como producción o
/// como UAT, no puede compartir SQLite, sesión, outbox, caché, config de
/// backend ni backups. Debe cumplirse en cualquier PC de cualquier cliente.
void main() {
  const uatNamespace = 'SistemaSolares_UAT';
  const prodNamespace = AppStorageNamespace.defaultFolderName;

  setUp(() {
    AppStorageNamespace.debugOverrideNamespace(null);
    // La suite inyecta un directorio de soporte compartido; se limpia para
    // ejercitar la resolución real de raíz (que SÍ depende del namespace).
    AppPaths.debugOverrideDefaultSupportDirectory(null);
  });

  tearDown(() {
    AppStorageNamespace.debugOverrideNamespace(null);
    AppPaths.debugOverrideDefaultSupportDirectory(null);
  });

  group('namespace (puro, sin estado global)', () {
    test('PROD conserva la carpeta histórica', () {
      expect(AppStorageNamespace.folderNameFor(prodNamespace), prodNamespace);
      expect(AppStorageNamespace.suffixFor(prodNamespace), isEmpty);
      expect(
        AppStorageNamespace.backupFolderNameFor(prodNamespace),
        AppStorageNamespace.defaultBackupFolderName,
      );
    });

    test('UAT obtiene una carpeta y un sufijo distintos', () {
      expect(AppStorageNamespace.folderNameFor(uatNamespace), uatNamespace);
      expect(AppStorageNamespace.suffixFor(uatNamespace), '_UAT');
      expect(
        AppStorageNamespace.backupFolderNameFor(uatNamespace),
        'FULLPOS_BACKUPS_UAT',
      );
    });

    test('la misma raíz + namespace distinto = rutas distintas', () {
      // Representa cualquier PC / cualquier perfil de Windows.
      const anyRoot = r'C:\Users\SomeCustomer\AppData\Local';
      final prodRoot = path.join(anyRoot, AppStorageNamespace.folderNameFor(prodNamespace));
      final uatRoot = path.join(anyRoot, AppStorageNamespace.folderNameFor(uatNamespace));

      expect(prodRoot, isNot(uatRoot));
      expect(path.isWithin(prodRoot, uatRoot), isFalse);
      expect(path.isWithin(uatRoot, prodRoot), isFalse);
    });

    test('un namespace inválido NO cae en la carpeta de producción', () {
      // Ningún intento de escape puede salir del directorio base.
      for (final hostile in [
        r'..\..\Windows',
        r'C:\Windows',
        '/etc/passwd',
        '   ',
        '...',
        r'..\SistemaSolares',
      ]) {
        final resolved = AppStorageNamespace.folderNameFor(hostile);
        expect(resolved, isNot(prodNamespace));
        expect(resolved, isNot(contains('/')));
        expect(resolved, isNot(contains(r'\')));
        expect(resolved, isNot(contains('..')));
      }
    });

    test('las claves sensibles (sesión) se separan por ambiente', () {
      const sessionKey = 'sync.jwt_token';
      expect(AppStorageNamespace.scopedKeyFor(prodNamespace, sessionKey), sessionKey);
      expect(
        AppStorageNamespace.scopedKeyFor(uatNamespace, sessionKey),
        'uat.$sessionKey',
      );
      expect(
        AppStorageNamespace.scopedKeyFor(uatNamespace, sessionKey),
        isNot(AppStorageNamespace.scopedKeyFor(prodNamespace, sessionKey)),
      );
    });
  });

  group('AppPaths por ambiente', () {
    // Captura EAGER: `supportDirectory` es `late final`, así que las rutas
    // deben leerse con el namespace correcto ya activo.
    Map<String, String> pathsFor(String namespace) {
      AppStorageNamespace.debugOverrideNamespace(namespace);
      final paths = AppPaths();
      return <String, String>{
        'root': paths.supportDirectory,
        'database': paths.databasePath,
        'cache': paths.cacheDatabasePath,
        'outbox': paths.outboxDatabasePath,
        'state': paths.deviceStateDatabasePath,
        'diagnosticsLog': paths.syncDiagnosticsLogPath,
        'log': paths.syncLogPath,
        'config': paths.configDirectory,
        'backups': paths.backupsDirectory,
        'defaultBackups': paths.defaultBackupDirectory,
      };
    }

    test('PROD y UAT calculan raíces distintas', () {
      final prod = pathsFor(prodNamespace);
      final uat = pathsFor(uatNamespace);

      expect(prod['root'], isNot(uat['root']));
    });

    test('SQLite, caché, outbox, estado y logs quedan separados', () {
      final prod = pathsFor(prodNamespace);
      final uat = pathsFor(uatNamespace);

      for (final key in <String>[
        'database',
        'cache',
        'outbox',
        'state',
        'diagnosticsLog',
        'log',
        'config',
        'backups',
      ]) {
        expect(prod[key], isNot(uat[key]), reason: 'PROD y UAT comparten $key');
      }
    });

    test('UAT no puede leer datos locales de PROD (ni al revés)', () {
      final prod = pathsFor(prodNamespace);
      final uat = pathsFor(uatNamespace);

      // Ninguna ruta de datos de un ambiente vive dentro de la raíz del otro.
      for (final key in <String>['database', 'cache', 'outbox', 'state']) {
        expect(
          path.isWithin(prod['root']!, uat[key]!),
          isFalse,
          reason: 'UAT $key vive dentro de la raíz PROD',
        );
        expect(
          path.isWithin(uat['root']!, prod[key]!),
          isFalse,
          reason: 'PROD $key vive dentro de la raíz UAT',
        );
      }
    });

    test('los logs alternos son identificables', () {
      final uat = pathsFor(uatNamespace);

      expect(uat['diagnosticsLog'], endsWith('sync_diagnostics.log'));
      expect(uat['root'], contains('_UAT'));
      expect(uat['defaultBackups'], contains('_UAT'));
      expect(AppStorageNamespace.label, 'ALTERNATE(_UAT)');
    });

    test('el namespace activo por defecto es producción', () {
      // Sin --dart-define=STORAGE_NAMESPACE el binario se comporta como
      // producción: ninguna ruta histórica cambia.
      expect(AppStorageNamespace.isDefault, isTrue);
      expect(AppStorageNamespace.isAlternate, isFalse);
      expect(AppStorageNamespace.folderName, AppStorageNamespace.defaultFolderName);
      expect(AppStorageNamespace.suffix, isEmpty);
      expect(AppStorageNamespace.label, 'PRODUCTION');
    });

    test('el backup profesional también se separa por ambiente', () {
      AppStorageNamespace.debugOverrideNamespace(prodNamespace);
      expect(AppStorageNamespace.backupFolderName, 'FULLPOS_BACKUPS');

      AppStorageNamespace.debugOverrideNamespace(uatNamespace);
      expect(AppStorageNamespace.backupFolderName, 'FULLPOS_BACKUPS_UAT');
    });
  });
}
