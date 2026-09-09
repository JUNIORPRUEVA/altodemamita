/// Global build/runtime flags.
///
/// `isProductionMode` defaults to `true` to match production hardening.
/// Override in local/dev/testing with:
/// `--dart-define=PRODUCTION_MODE=false`
const bool isProductionMode = bool.fromEnvironment(
  'PRODUCTION_MODE',
  defaultValue: true,
);

/// Enables legacy database migration/rehydration.
///
/// This is intentionally `false` by default and must be explicitly enabled.
/// Use: `--dart-define=ALLOW_LEGACY_MIGRATION=true`
const bool allowLegacyMigration = bool.fromEnvironment(
  'ALLOW_LEGACY_MIGRATION',
  defaultValue: false,
);

/// When true, no background polling, queue retry loop, or startup sync runs.
/// Explicit manual sync actions remain available.
///
/// The clean Solares Owner backend is upload-only from the desktop app by
/// default, so the client PC can push its local data to the cloud
/// automatically without enabling cloud -> local restore.
const bool manualCloudSyncOnly = bool.fromEnvironment(
  'MANUAL_CLOUD_SYNC_ONLY',
  defaultValue: false,
);

/// Master switch for cloud -> local downloads.
///
/// Default is `false` for safe containment mode (FASE 0): local -> cloud
/// uploads stay active while any cloud pull is blocked.
/// Use: `--dart-define=ALLOW_CLOUD_PULL=true`
const bool allowCloudPull = bool.fromEnvironment(
  'ALLOW_CLOUD_PULL',
  defaultValue: false,
);

/// Allows controlled cloud bootstrap for authentication data only
/// (users/roles/permissions and related auth scopes).
///
/// This is intentionally independent from [allowCloudPull].
/// Use: `--dart-define=ALLOW_AUTH_BOOTSTRAP=true`
const bool allowAuthBootstrap = bool.fromEnvironment(
  'ALLOW_AUTH_BOOTSTRAP',
  defaultValue: false,
);

/// Enables manual emergency cloud -> local restore flows.
///
/// Defaults to `false` and should remain disabled for normal operation.
/// Use: `--dart-define=ALLOW_MANUAL_CLOUD_RESTORE=true`
const bool allowManualCloudRestore = bool.fromEnvironment(
  'ALLOW_MANUAL_CLOUD_RESTORE',
  defaultValue: false,
);

/// Phase 2 transition mode.
///
/// Supported values:
/// - LEGACY_LOCAL: current SQLite-authoritative behavior.
/// - CLOUD_UAT: use cloud foundation services only in controlled UAT.
/// - CLOUD_AUTHORITATIVE: backend-authoritative mode after final approval.
const String cloudCutoverModeValue = String.fromEnvironment(
  'CLOUD_CUTOVER_MODE',
  defaultValue: 'LEGACY_LOCAL',
);

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
