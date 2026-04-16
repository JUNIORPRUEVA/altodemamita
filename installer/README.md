# Release Windows

Esta carpeta queda preparada para empaquetar la aplicacion real de este proyecto con Inno Setup usando el bundle completo de Flutter Windows.

## Auditoria corta

- El build release actual si genera el bundle completo requerido por Flutter Desktop: `sistema_solares.exe`, `flutter_windows.dll`, `sqlite3.dll`, `printing_plugin.dll`, `pdfium.dll`, `data\app.so`, `data\icudtl.dat` y `data\flutter_assets\...`.
- La app no arranca leyendo archivos relativos dentro de `Program Files` para su estado persistente. La base SQLite, configuracion, logs, recovery y archivos generados se crean en `%LOCALAPPDATA%\SistemaSolares\...`.
- La ruta de backup por defecto se crea en `%USERPROFILE%\Documents\SistemaSolares\Backups`, fuera del directorio instalado.
- El runtime critico para este build es Microsoft Visual C++ Redistributable x64.
- No se detecto ningun plugin o referencia activa a WebView/WebView2 en el build actual de Windows. Por eso el script de produccion deja WebView2 como opcional y no como requisito por defecto.
- Riesgo principal detectado: distribuir solo el `.exe` o un bundle parcial. En Windows Flutter eso rompe el arranque aunque el ejecutable exista.

## Que toma el instalador

- Nombre del producto: `Sistema Solares`
- Ejecutable: `sistema_solares.exe`
- Icono del setup: `windows/runner/resources/app_icon.ico`
- Release Flutter esperado: `build/windows/x64/runner/Release`
- Redistributable requerido: `installer/redist/VC_redist.x64.exe`
- WebView2 opcional: `installer/redist/MicrosoftEdgeWebView2RuntimeInstallerX64.exe` solo si un futuro build agrega un plugin que realmente lo use

## Checklist de prebuild

Antes de compilar el instalador, confirma lo siguiente en `build/windows/x64/runner/Release`:

- `sistema_solares.exe`
- `flutter_windows.dll`
- `sqlite3.dll`
- `printing_plugin.dll`
- `pdfium.dll`
- `data\app.so`
- `data\icudtl.dat`
- `data\flutter_assets\AssetManifest.bin`
- `data\flutter_assets\FontManifest.json`
- `data\flutter_assets\NativeAssetsManifest.json`
- `data\flutter_assets\NOTICES.Z`
- `data\flutter_assets\assets\fonts\...`
- `data\flutter_assets\fonts\MaterialIcons-Regular.otf`

Si falta cualquiera de esos archivos o carpetas, no compiles el instalador todavia. Primero vuelve a generar el release de Flutter.

## Preparar sin compilar

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\windows_release.ps1
```

Ese comando:

- valida assets y redistributables
- prepara la ruta ASCII segura para Windows (`C:\dev\sistema_solares_ascii`)
- crea `installer/output` si hace falta
- calcula la version desde `pubspec.yaml`
- no compila Flutter ni genera el instalador

## Generar release mas adelante

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\windows_release.ps1 -Build -CompileInstaller
```

Ese flujo:

- recompila el release completo de Flutter para Windows
- toma el directorio `build/windows/x64/runner/Release` entero, no solo el ejecutable
- compila `installer/setup.iss`
- genera un instalador por maquina en `Program Files`, con acceso directo de menu inicio, opcion de icono de escritorio, desinstalador y opcion de abrir la app al final

La version sale de `pubspec.yaml`. Si quieres forzar otra version puntual:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\windows_release.ps1 -Build -CompileInstaller -Version 1.2.0+5
```

## Overrides opcionales en setup.iss

El script ya compila con los datos reales del proyecto actual. Si luego quieres personalizar despliegues concretos, `setup.iss` acepta estos defines opcionales:

- `MyAppPublisher`
- `MyAppPublisherURL`
- `MyAppSupportURL`
- `SupportLabel`
- `MyAppLicenseFile`
- `BrandWizardImage`
- `BrandWizardSmallImage`
- `IncludeWebView2Runtime=1` solo si el build llega a necesitar WebView2

Ejemplo manual con ISCC:

```powershell
ISCC .\installer\setup.iss /DMyAppVersion=1.2.0+5 /DMyAppVersionInfo=1.2.0.5
```