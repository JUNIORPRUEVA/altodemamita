# Sistema Solares UI

Panel web de supervision y administracion separado de la app Windows.

## Alcance

- Dashboard ejecutivo
- Reportes en solo lectura
- Clientes en solo lectura
- Usuarios con CRUD
- Configuracion y estado del sistema

## Restricciones

- No crea ventas
- No edita ventas
- No registra pagos
- No trabaja cuotas
- No ejecuta caja
- No usa SQLite ni modo offline

## Autenticacion y acceso

- JWT contra el backend NestJS
- Rutas protegidas en frontend
- `admin`: dashboard, reportes, clientes, usuarios y configuracion
- `viewer`: dashboard, reportes y clientes en solo lectura

## Ejecucion local

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000/api
```

## Build web

```bash
flutter build web --release --base-href / --dart-define=API_BASE_URL=http://localhost:3000/api
```

El build genera la carpeta `build/web` lista para despliegue. En release, Flutter deja activo el service worker (`flutter_service_worker.js`) y entrega artefactos minificados para la PWA.

## Producción con Docker + Nginx

Construcción de imagen:

```bash
docker build -t sistema-solares-ui ./sistema_solares_ui
```

Ejecución con URL del backend configurable en runtime:

```bash
docker run --rm -p 80:80 \
	-e API_BASE_URL=https://api.tudominio.com/api \
	sistema-solares-ui
```

La imagen:

- sirve la PWA con `nginx:alpine`
- redirige todas las rutas a `index.html` para compatibilidad SPA
- activa `gzip`
- evita cache agresiva sobre `index.html`, `manifest.json`, `flutter_service_worker.js` y `app-config.json`
- cachea assets estáticos con `immutable`

## EasyPanel

Variables recomendadas:

- `API_BASE_URL=https://api.tudominio.com/api`

Puerto expuesto por la imagen:

- `80`

La app usará `app-config.json` generado al arrancar el contenedor, por lo que puedes cambiar la URL del backend desde EasyPanel sin reconstruir la imagen.

## Realtime

La PWA consume la API REST bajo `API_BASE_URL` y se conecta al namespace Socket.IO `/realtime` derivado de esa URL.
