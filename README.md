# Sistema Solares

Monorepo del Sistema de Gestión de Ventas de Solares.

## Estructura del proyecto

```
SISTEMA_SOLARES/
├── app_local/       # App Flutter Windows (principal/local)
├── app_owner/       # App móvil Owner/APK (solo lectura)
├── backend/         # Backend Node.js + Prisma + PostgreSQL
├── docs/            # Documentación técnica
├── tools/           # Scripts de utilidad, auditoría e instalador
├── backups/         # Respaldos de base de datos
├── backups_audit/   # Respaldos de auditoría
├── .vscode/         # Configuración de VS Code (launch.json)
└── README.md
```

## Requisitos

- Flutter SDK (estable)
- Node.js 20+
- PostgreSQL
- npm

## Comandos de desarrollo

### Backend local

```bash
cd backend
npm install
npm run build
npm start
```

### App local Windows

```bash
cd app_local
flutter pub get
flutter run -d windows --dart-define=SYNC_API_BASE_URL=http://localhost:3000
```

### App Owner Android/emulador

```bash
cd app_owner
flutter pub get
flutter run -d emulator --dart-define=OWNER_API_BASE_URL=http://10.0.2.2:3000
```

## Build de producción

### App local Windows

```bash
cd app_local
flutter build windows --dart-define=SYNC_API_BASE_URL=https://URL_BACKEND_PRODUCCION
```

### App Owner APK

```bash
cd app_owner
flutter build apk --dart-define=OWNER_API_BASE_URL=https://URL_BACKEND_PRODUCCION
```

## VS Code Launch Configurations

El archivo `.vscode/launch.json` incluye configuraciones para:

- **App Local DEV**: Flutter Windows con `SYNC_API_BASE_URL=http://localhost:3000`
- **App Owner DEV**: Flutter Android/emulador con `OWNER_API_BASE_URL=http://10.0.2.2:3000`
- **Backend DEV**: Node.js con `npm run dev`
