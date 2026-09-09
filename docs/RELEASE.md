# Sistema Solares Release Notes

## 2026-09-08 Finalization Sprint

Status: backend deployed, public HTTPS route verified, and Windows installer generated for the production backend.

### Backend

- Production server: `31.97.99.70`
- EasyPanel project: `altomamita`
- Production backend service: `altomamita_altomamita-backend`
- Production database service: `altomamita_altomamita-db`
- Deployed backend image: `altomamita_altomamita-backend:prod-finalization-20260908T201059Z`
- Image ID: `sha256:2e93a274c13e7177be6c2800634955dd36aa7086700625913dcfa243ba0bb51b`
- Previous rollback image: `altomamita_altomamita-backend:prod-shell-phase1f-20260908`
- Health check after deploy: internal `/api/health` returned `{"ok":true,"service":"sistema-solares-backend"}`
- Public backend URL: `https://altomamita-backend.gcdndd.easypanel.host`
- Public `/api/health`: HTTP `200`, TLS verification `0`
- Public HTTP redirect: `http://altomamita-backend.gcdndd.easypanel.host/api/health` redirects to HTTPS with HTTP `301`
- Public `/api/system/status`: HTTP `200`, database `altomamita`, `initialUploadRequired=true`

### Production Database Gate

Pre-deploy production business row counts were empty:

- `Client=0`
- `Seller=0`
- `Lot=0`
- `Sale=0`
- `Installment=0`
- `Payment=0`

Post-deploy counts remained empty for the same business tables. No customer business data was imported during this sprint.

Final public status after installer build still reported empty production business counts:

- `clients=0`
- `sellers=0`
- `lots=0`
- `sales=0`
- `installments=0`
- `payments=0`
- `syncBatches=0`

### Backup

- Pre-deploy dump: `/etc/easypanel/projects/altomamita/backups/pre-deployment/altomamita_predeploy_20260908T201049Z.dump`
- SHA256: `d304870c66d4de7281596a3e1be0285ab5efda19eaf4d6b80714d6f0354b6bf8`
- Size: `73951` bytes
- Verification: `pg_restore -l` succeeded against the dump.

### Schema

Applied Prisma migrations in production:

- `20260616170000_initial_owner_sync`
- `20260616213000_add_company_tenant_scope`
- `20260616220000_add_partial_unique_indexes`
- `20260727090000_add_payment_reminder_notifications`
- `20260908090000_phase_1a_cloud_authoritative_model_foundation`
- `20260908110000_phase_1d_authoritative_sale_payment_foundation`

### Desktop Release Gate

The desktop application no longer has a baked-in EasyPanel backend default. Release builds now require an explicit `-SyncApiBaseUrl` and refuse legacy `onqyr1.easypanel.host` or `25432` values.

Final release build:

- Installer: `app_local/instalacion/output/SistemaSolares_Setup_1.0.0_15.exe`
- SHA256: `71A6D955A8BFB97BE83DF52176A786B781845B29756CDCC80755C0F47144AA93`
- Size: `33805491` bytes
- Version: `1.0.0+15`
- Sync API URL: `https://altomamita-backend.gcdndd.easypanel.host`
- `ALLOW_CLOUD_PULL=True`
- `CLOUD_CUTOVER_MODE=CLOUD_AUTHORITATIVE`
- Release smoke: `sistema_solares.exe` started and stayed alive for 12 seconds under an isolated temporary `LOCALAPPDATA`.
- Runtime stale-host scan: no hits for `onqyr1`, `25432`, old misspelled EasyPanel hostnames, UAT backend, or acceptance hostnames.

Generic `localhost` / `127.0.0.1` strings remain in compiled output from diagnostic/help text and development detection logic; they are not the configured production endpoint.

### Local Validation

- Backend tests: `npm test` passed, 40 tests.
- Backend build: `npm run build` passed.
- Flutter analyze: passed.
- Flutter tests with cloud pull enabled: `flutter test --concurrency=1 --dart-define=ALLOW_CLOUD_PULL=true` passed after URL hardening, 391 tests.
- Final installer build: passed with production URL, cloud pull enabled, and `CLOUD_AUTHORITATIVE` cutover mode.

### Known Residual Risk

- Docker build reported 3 moderate npm audit findings from installed dependencies. No automatic dependency upgrade was performed during this production finalization sprint.
- Docker reported `JSONArgsRecommended` for the shell-form `CMD`; this is operationally non-blocking but should be cleaned in a later low-risk backend Dockerfile pass.
- Authenticated public login/refresh/me smoke was not completed from this workstation because SSH access to retrieve bootstrap credentials was unavailable (`Permission denied`) and no bootstrap password is stored locally.
