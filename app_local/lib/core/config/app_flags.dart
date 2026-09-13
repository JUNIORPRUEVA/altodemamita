import 'runtime_config.dart';

/// Global build/runtime flags.
///
/// `isProductionMode` defaults to `true` to match production hardening.
/// Override in local/dev/testing with:
/// `--dart-define=PRODUCTION_MODE=false`
const bool _isProductionModeFromEnv = bool.fromEnvironment(
  'PRODUCTION_MODE',
  defaultValue: true,
);
bool get isProductionMode =>
    runtimeConfigBool('PRODUCTION_MODE', _isProductionModeFromEnv);

/// Enables legacy database migration/rehydration.
///
/// This is intentionally `false` by default and must be explicitly enabled.
/// Use: `--dart-define=ALLOW_LEGACY_MIGRATION=true`
const bool _allowLegacyMigrationFromEnv = bool.fromEnvironment(
  'ALLOW_LEGACY_MIGRATION',
  defaultValue: false,
);
bool get allowLegacyMigration =>
    runtimeConfigBool('ALLOW_LEGACY_MIGRATION', _allowLegacyMigrationFromEnv);

/// When true, no background polling, queue retry loop, or startup sync runs.
/// Explicit manual sync actions remain available.
///
/// The clean Solares Owner backend is upload-only from the desktop app by
/// default, so the client PC can push its local data to the cloud
/// automatically without enabling cloud -> local restore.
const bool _manualCloudSyncOnlyFromEnv = bool.fromEnvironment(
  'MANUAL_CLOUD_SYNC_ONLY',
  defaultValue: false,
);
bool get manualCloudSyncOnly =>
    runtimeConfigBool('MANUAL_CLOUD_SYNC_ONLY', _manualCloudSyncOnlyFromEnv);

/// Master switch for cloud -> local downloads.
///
/// Default is `false` for safe containment mode (FASE 0): local -> cloud
/// uploads stay active while any cloud pull is blocked.
/// Use: `--dart-define=ALLOW_CLOUD_PULL=true`
const bool _allowCloudPullFromEnv = bool.fromEnvironment(
  'ALLOW_CLOUD_PULL',
  defaultValue: false,
);
bool get allowCloudPull =>
    runtimeConfigBool('ALLOW_CLOUD_PULL', _allowCloudPullFromEnv);

/// Allows controlled cloud bootstrap for authentication data only
/// (users/roles/permissions and related auth scopes).
///
/// This is intentionally independent from [allowCloudPull].
/// Use: `--dart-define=ALLOW_AUTH_BOOTSTRAP=true`
const bool _allowAuthBootstrapFromEnv = bool.fromEnvironment(
  'ALLOW_AUTH_BOOTSTRAP',
  defaultValue: false,
);
bool get allowAuthBootstrap =>
    runtimeConfigBool('ALLOW_AUTH_BOOTSTRAP', _allowAuthBootstrapFromEnv);

/// Enables manual emergency cloud -> local restore flows.
///
/// Defaults to `false` and should remain disabled for normal operation.
/// Use: `--dart-define=ALLOW_MANUAL_CLOUD_RESTORE=true`
const bool _allowManualCloudRestoreFromEnv = bool.fromEnvironment(
  'ALLOW_MANUAL_CLOUD_RESTORE',
  defaultValue: false,
);
bool get allowManualCloudRestore => runtimeConfigBool(
  'ALLOW_MANUAL_CLOUD_RESTORE',
  _allowManualCloudRestoreFromEnv,
);

/// Enables a browser-only diagnostic entry point for PWA runtime validation.
///
/// This must stay disabled in normal builds. Use only for local QA:
/// `--dart-define=PWA_RUNTIME_DIAGNOSTIC=true`
const bool _pwaRuntimeDiagnosticFromEnv = bool.fromEnvironment(
  'PWA_RUNTIME_DIAGNOSTIC',
  defaultValue: false,
);
bool get pwaRuntimeDiagnostic =>
    runtimeConfigBool('PWA_RUNTIME_DIAGNOSTIC', _pwaRuntimeDiagnosticFromEnv);

/// Phase 2 transition mode.
///
/// Supported values:
/// - LEGACY_LOCAL: current SQLite-authoritative behavior.
/// - CLOUD_UAT: use cloud foundation services only in controlled UAT.
/// - CLOUD_AUTHORITATIVE: backend-authoritative mode after final approval.
const String _cloudCutoverModeValueFromEnv = String.fromEnvironment(
  'CLOUD_CUTOVER_MODE',
  defaultValue: 'LEGACY_LOCAL',
);
String get cloudCutoverModeValue =>
    runtimeConfigString('CLOUD_CUTOVER_MODE', _cloudCutoverModeValueFromEnv);

enum CloudCutoverMode {
  legacyLocal,
  cloudUat,
  cloudAuthoritative;

  bool get usesAuthoritativeBusinessWrites =>
      this == CloudCutoverMode.cloudUat ||
      this == CloudCutoverMode.cloudAuthoritative;

  bool get blocksLegacyFinancialSync =>
      this == CloudCutoverMode.cloudUat ||
      this == CloudCutoverMode.cloudAuthoritative;
}

CloudCutoverMode get cloudCutoverMode {
  switch (cloudCutoverModeValue.trim().toUpperCase()) {
    case 'CLOUD_UAT':
      return CloudCutoverMode.cloudUat;
    case 'CLOUD_AUTHORITATIVE':
      return CloudCutoverMode.cloudAuthoritative;
    case 'LEGACY_LOCAL':
    default:
      return CloudCutoverMode.legacyLocal;
  }
}
