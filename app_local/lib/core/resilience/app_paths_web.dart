import 'package:path/path.dart' as p;

/// Implementación WEB de [AppPaths].
///
/// En el navegador NO existe sistema de archivos, `LOCALAPPDATA`, `D:\` ni
/// `Platform.environment`. Esta implementación expone las mismas rutas
/// lógicas para que el resto del sistema (esquema, repositorios, servicios)
/// compile y funcione sin ramificaciones `kIsWeb` dispersas.
///
/// Importante:
/// - Las rutas devueltas son **identificadores virtuales**, no rutas reales
///   del sistema de archivos. `sqflite_common_ffi_web` las usa como clave de
///   la base de datos dentro de IndexedDB.
/// - Cualquier código que necesite archivos reales (backup, restore,
///   impresión nativa, logs en disco) debe consultar
///   [supportsFileSystem] y desactivarse.
class AppPaths {
  AppPaths({String? supportDirectory}) : _supportDirectory = supportDirectory;

  final String? _supportDirectory;

  /// En web el sistema de archivos NO está disponible.
  bool get supportsFileSystem => false;

  late final String supportDirectory =
      _supportDirectory ?? p.posix.join('/', 'SistemaSolares');

  /// En web no existe el directorio heredado de versiones antiguas.
  String get legacySupportDirectory => supportDirectory;

  String get dataDirectory => p.posix.join(supportDirectory, 'data');
  String get databaseDirectory => p.posix.join(dataDirectory, 'database');
  String get databasePath =>
      p.posix.join(databaseDirectory, 'sistema_solares.db');
  String get dataCacheDirectory => p.posix.join(dataDirectory, 'cache');
  String get dataOutboxDirectory => p.posix.join(dataDirectory, 'outbox');
  String get dataStateDirectory => p.posix.join(dataDirectory, 'state');
  String get cacheDatabasePath =>
      p.posix.join(dataCacheDirectory, 'cache.db');
  String get outboxDatabasePath =>
      p.posix.join(dataOutboxDirectory, 'outbox.db');
  String get deviceStateDatabasePath =>
      p.posix.join(dataStateDirectory, 'device_state.db');
  String get backupsDirectory => p.posix.join(supportDirectory, 'backups');
  String get localBackupsDirectory => p.posix.join(backupsDirectory, 'local');

  /// En web no existe almacenamiento en discos externos.
  String get professionalLocalBackupsDirectory => localBackupsDirectory;

  String get configDirectory => p.posix.join(supportDirectory, 'config');
  String get logsDirectory => p.posix.join(supportDirectory, 'logs');
  String get syncLogPath => p.posix.join(logsDirectory, 'sync.log');
  String get syncDiagnosticsLogPath =>
      p.posix.join(logsDirectory, 'sync_diagnostics.log');
  String get incidentsDirectory => p.posix.join(logsDirectory, 'incidents');
  String get generatedDirectory => p.posix.join(supportDirectory, 'generated');
  String get mediaDirectory => p.posix.join(supportDirectory, 'media');
  String get tempDirectory => p.posix.join(supportDirectory, 'temp');
  String get cacheDirectory => p.posix.join(supportDirectory, 'cache');
  String get migrationDirectory => p.posix.join(supportDirectory, 'migration');
  String get recoveryDirectory => p.posix.join(supportDirectory, 'recovery');
  String get quarantineDirectory =>
      p.posix.join(recoveryDirectory, 'quarantine');
  String get snapshotsDirectory => p.posix.join(recoveryDirectory, 'snapshots');
  String get backupConfigPath =>
      p.posix.join(configDirectory, 'backup_config.json');
  String get backupHistoryPath =>
      p.posix.join(configDirectory, 'backup_history.json');
  String get legacyBackupConfigPath => backupConfigPath;
  String get legacyBackupHistoryPath => backupHistoryPath;

  /// En web los respaldos se realizan exportando la base de datos, no
  /// copiando archivos a una carpeta.
  String get defaultBackupDirectory => backupsDirectory;

  /// No hay directorios que crear en el navegador.
  ///
  /// Los almacenes reales (IndexedDB / SQLite WASM) se crean por sí mismos.
  Future<void> ensureCriticalDirectories() async {}

  /// No hay archivos temporales en disco que limpiar en el navegador.
  Future<void> cleanTransientFiles({
    Duration maxAge = const Duration(days: 2),
  }) async {}
}
