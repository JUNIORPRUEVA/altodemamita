/// Namespace de almacenamiento local de la aplicación.
///
/// El mismo binario puede instalarse como PRODUCCIÓN o como UAT y mantener
/// datos 100% aislados (SQLite, sesión, outbox, caché, logs, backups).
///
/// - PRODUCCIÓN (valor por defecto): `SistemaSolares`
///   Conserva EXACTAMENTE las rutas históricas. No se mueve ni se migra
///   ningún dato existente del cliente.
/// - UAT: `SistemaSolares_UAT` (vía `--dart-define=STORAGE_NAMESPACE=...`)
///
/// El nombre se normaliza para que nunca pueda escapar del directorio base
/// (se eliminan separadores de ruta, `..`, espacios y caracteres extraños).
library;

class AppStorageNamespace {
  const AppStorageNamespace._();

  /// Carpeta histórica de producción. NO cambiar: los clientes ya tienen sus
  /// datos ahí.
  static const String defaultFolderName = 'SistemaSolares';

  /// Carpeta histórica de backups profesionales de producción.
  static const String defaultBackupFolderName = 'FULLPOS_BACKUPS';

  /// Valor inyectado en build (`--dart-define=STORAGE_NAMESPACE=...`).
  static const String rawConfiguredNamespace = String.fromEnvironment(
    'STORAGE_NAMESPACE',
    defaultValue: defaultFolderName,
  );

  static String? _debugOverride;

  /// Override para pruebas (mismo patrón que
  /// `AppPaths.debugOverrideDefaultSupportDirectory`).
  static String? get debugNamespaceOverride => _debugOverride;

  static void debugOverrideNamespace(String? value) {
    _debugOverride = value;
  }

  static String get _raw => _debugOverride ?? rawConfiguredNamespace;

  /// `true` cuando el build usa el namespace histórico de producción.
  static bool get isDefault => folderName == defaultFolderName;

  /// `true` para builds de UAT / ambientes alternos.
  static bool get isAlternate => !isDefault;

  /// Nombre de carpeta saneado (sin separadores ni rutas relativas).
  static String get folderName => folderNameFor(_raw);

  /// Sufijo de ambiente derivado del namespace (`''` en producción).
  ///
  /// `SistemaSolares_UAT` -> `'_UAT'`
  static String get suffix => suffixFor(_raw);

  /// Carpeta de backups profesionales (`FULLPOS_BACKUPS` / `FULLPOS_BACKUPS_UAT`).
  static String get backupFolderName => backupFolderNameFor(_raw);

  /// Etiqueta legible para diagnósticos y logs.
  static String get label => isDefault ? 'PRODUCTION' : 'ALTERNATE($suffix)';

  /// Prefija claves de almacenamiento sensible (Credential Manager,
  /// SharedPreferences) para que la sesión de UAT no comparta con producción.
  /// En producción devuelve la clave intacta.
  static String scopedKey(String key) => scopedKeyFor(_raw, key);

  /// Nombre de carpeta calculado para un namespace arbitrario.
  ///
  /// Sólo se acepta un nombre que YA sea válido (`[A-Za-z0-9_-]`, hasta 64).
  /// Cualquier otra cosa —vacío, rutas (`..\SistemaSolares`), unidades o
  /// símbolos— NO cae jamás en la carpeta de producción: se degrada a un
  /// nombre alterno para no arriesgar escribir sobre los datos reales del
  /// cliente.
  static String folderNameFor(String rawNamespace) {
    final trimmed = rawNamespace.trim();
    if (!_validFolderNamePattern.hasMatch(trimmed)) {
      return '${defaultFolderName}_ALT';
    }
    return trimmed;
  }

  static final RegExp _validFolderNamePattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// Sufijo calculado para un namespace arbitrario.
  static String suffixFor(String rawNamespace) {
    final name = folderNameFor(rawNamespace);
    if (name == defaultFolderName) {
      return '';
    }
    final stripped = name.startsWith(defaultFolderName)
        ? name.substring(defaultFolderName.length)
        : name;
    final normalized = stripped.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return normalized.isEmpty ? '_ALT' : '_$normalized';
  }

  /// Carpeta de backups profesionales para un namespace arbitrario.
  static String backupFolderNameFor(String rawNamespace) =>
      '$defaultBackupFolderName${suffixFor(rawNamespace)}';

  /// Clave con alcance de ambiente para un namespace arbitrario.
  static String scopedKeyFor(String rawNamespace, String key) {
    final suffixValue = suffixFor(rawNamespace);
    if (suffixValue.isEmpty) {
      return key;
    }
    final prefix = suffixValue.replaceFirst('_', '').toLowerCase();
    return prefix.isEmpty ? key : '$prefix.$key';
  }
}
