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
