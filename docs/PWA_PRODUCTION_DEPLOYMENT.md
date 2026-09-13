# Sistema Solares PWA Production Deployment

## Target

- EasyPanel project: `altomamita`
- EasyPanel service: `altodemamita-pwa`
- Source type: Git repository
- Branch: `main`
- Build context: `app_local`
- Dockerfile: `Dockerfile.pwa`
- Container port: `80`
- Health check: `GET /`
- Backend: `https://altomamita-backend.gcdndd.easypanel.host`

The PWA is a static Flutter Web build served by Nginx. It does not create or own
any database. PostgreSQL remains owned by the backend service.

## Runtime Variables

These values are non-secret frontend runtime settings and must be configured in
EasyPanel at the `altodemamita-pwa` service level:

| Variable | Production value |
| --- | --- |
| `SYNC_API_BASE_URL` | `https://altomamita-backend.gcdndd.easypanel.host` |
| `CLOUD_CUTOVER_MODE` | `CLOUD_AUTHORITATIVE` |
| `ALLOW_CLOUD_PULL` | `true` |
| `ALLOW_LEGACY_MIGRATION` | `false` |
| `ALLOW_AUTH_BOOTSTRAP` | `false` |

Optional hardening defaults:

| Variable | Default |
| --- | --- |
| `ALLOW_MANUAL_CLOUD_RESTORE` | `false` |
| `MANUAL_CLOUD_SYNC_ONLY` | `false` |
| `PRODUCTION_MODE` | `true` |
| `PWA_RUNTIME_DIAGNOSTIC` | `false` |

The container startup script generates `/usr/share/nginx/html/runtime-config.js`
from service environment variables. Updating these variables requires restarting
or redeploying the PWA container, but it does not require rebuilding Flutter.

Runtime precedence for Web:

1. Valid `runtime-config.js` value.
2. Compiled `--dart-define` fallback.
3. Safe default.

Empty runtime values do not erase compiled fallback values.

## Nginx

The PWA uses `app_local/nginx.conf`.

- `/` and `/index.html` are served with `Cache-Control: no-store`.
- `/runtime-config.js` is served with `Cache-Control: no-store`.
- Hashed static assets may be cached long-term.
- SPA routes fall back to `/index.html`, so refresh on internal routes does not
  return Nginx 404.

## Deploy

1. Ensure `main` is pushed.
2. In EasyPanel project `altomamita`, create service `altodemamita-pwa`.
3. Set source to the Git repository for this project.
4. Set branch to `main`.
5. Set build context to `app_local`.
6. Set Dockerfile to `Dockerfile.pwa`.
7. Set exposed/internal port to `80`.
8. Configure the runtime variables listed above.
9. Configure a domain to service `altodemamita-pwa`, port `80`.
10. Enable HTTPS.
11. Deploy and verify the service is running and healthy.

## Smoke Checks

- `GET /` returns `200`.
- `GET /runtime-config.js` returns the configured non-secret runtime values.
- `GET /manifest.json` returns `200`.
- Flutter bootstrap files load without 404.
- Refresh on `/` and internal routes loads the app.
- Login uses the cloud backend and does not show local setup/bootstrap.
- Mobile viewport checks: `390x844` and `430x932`.
- PWA installability: manifest, icons, service worker, HTTPS.

## CORS

The backend must allow the deployed PWA origin explicitly in production. Avoid
open origin reflection for public production traffic. Local development may keep
localhost origins.

If CORS requires backend changes, deploy them as a separate backend-controlled
change with tests. Do not run database migrations for the PWA deploy.

## Rollback

Record after every deployment:

- commit SHA
- image tag
- image ID
- previous known-good image tag

Rollback options:

1. In EasyPanel, redeploy the previous known-good image/tag if available.
2. Or set source back to the previous known-good commit and redeploy.
3. Confirm `GET /` returns `200` and login reaches the backend.

Rollback does not require database changes.

## Production Safety

- No production database mutation is required.
- No SQLite import is required.
- No new PostgreSQL service is required.
- Do not deploy `app_owner` from this service.
- Do not place secrets in frontend runtime variables.
