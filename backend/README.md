# Sistema Solares Backend

Backend profesional en NestJS para ventas, financiamiento y pagos. Diseñado para servir a Flutter Windows, app móvil APK y PWA.

## Stack

- NestJS
- TypeScript
- Prisma
- PostgreSQL
- JWT Authentication
- Soft delete y sync status en todas las entidades

## Módulos incluidos

- Auth
- Clientes
- Productos
- Ventas
- Pagos
- Cuotas
- Reportes
- Sync
- Realtime WebSocket

## Requisitos

- Node.js 20+
- PostgreSQL 14+

## Instalación

```bash
cd backend
npm install
copy .env.example .env
```

Configura `JWT_SECRET` y una de estas opciones de base de datos en `.env`:

- `DATABASE_URL`
- `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`, `DB_NAME` y opcionalmente `DB_SCHEMA`

## Migraciones y seed

```bash
npm run prisma:generate
npm run prisma:migrate
npm run prisma:seed
```

Usuario inicial del seed:

- email: `admin@sistemasolares.local`
- usuario: `superadmin`
- clave: `Admin12345*`

## Desarrollo

```bash
npm run start:dev
```

La API quedará en:

- `http://localhost:3000/api`

## Producción con Docker

Construcción de imagen:

```bash
docker build -t sistema-solares-backend ./backend
```

Ejecución del contenedor:

```bash
docker run --rm -p 3000:3000 \
	-e NODE_ENV=production \
	-e PORT=3000 \
	-e DB_HOST=postgres \
	-e DB_PORT=5432 \
	-e DB_USERNAME=postgres \
	-e DB_PASSWORD=postgres \
	-e DB_NAME=sistema_solares_backend \
	-e JWT_SECRET=replace_with_a_strong_secret \
	sistema-solares-backend
```

El contenedor de producción:

- usa `node:20-alpine`
- compila en una etapa separada
- elimina `devDependencies` de la imagen final
- ejecuta como usuario no root
- ejecuta `prisma migrate deploy` antes de arrancar la API
- arranca con `node dist/main.js`

Si vas a desplegar en EasyPanel, puedes cargar esas variables directamente en el panel y usar el comando por defecto de la imagen.

Si tu despliegue ya estaba construido con una imagen anterior, debes reconstruir y redeplegar para que las migraciones pendientes se apliquen en la base remota al iniciar.

Para el panel web define al menos uno de estos valores:

- `PANEL_WEB_ORIGIN=https://altodemamita.com`
- `PANEL_WEB_ORIGINS=https://altodemamita.com,https://www.altodemamita.com,https://altodemanita-altodemamita-pwa.onqyr1.easypanel.host`

`PANEL_WEB_ORIGINS` permite múltiples dominios del panel y mantiene REST + WebSocket autorizados al mismo tiempo.

## Endpoints principales

- `POST /api/auth/login`
- `GET /api/auth/me`
- `GET|POST|PATCH|DELETE /api/auth/users`
- `GET|POST|PATCH|DELETE /api/clients`
- `GET|POST|PATCH|DELETE /api/products`
- `GET|POST|PATCH|DELETE /api/sales`
- `GET|POST|PATCH|DELETE /api/installments`
- `GET|POST|PATCH|DELETE /api/payments`
- `GET /api/reports/summary`
- `GET /api/reports/sales`
- `GET /api/reports/payments`
- `GET /api/reports/delinquency`
- `POST /api/sync/upload`
- `GET /api/sync/download`
- `GET /api/sync/jobs/:jobId`

## Sincronización rápida

- `POST /api/sync/upload` ahora responde rápido con `202 Accepted`
- el lote se encola en memoria para procesamiento asíncrono
- el estado del trabajo puede consultarse en `GET /api/sync/jobs/:jobId`

## Tiempo real

Gateway WebSocket disponible en:

- `ws://localhost:3000/realtime`

Eventos emitidos:

- `sync.job.accepted`
- `sync.job.started`
- `sync.job.completed`
- `sync.job.failed`
- `sale.created`
- `payment.created`
- `entity.updated`

## Autorización

Usa Bearer Token JWT:

```http
Authorization: Bearer <token>
```

Los permisos se asignan a roles y los roles a usuarios.

## Notas de integración

- Todas las tablas usan UUID.
- Todas incluyen `created_at`, `updated_at`, `deleted_at`, `sync_status`.
- `deleted_at` implementa soft delete.
- `sync_status` permite integración offline/online y sincronización por lotes.