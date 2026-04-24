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
const bool manualCloudSyncOnly = bool.fromEnvironment(
  'MANUAL_CLOUD_SYNC_ONLY',
  defaultValue: true,
);
