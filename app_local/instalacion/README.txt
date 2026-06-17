Sistema Solares - Instalador Windows

Carpeta generada para app_local version 1.0.0+10.

Archivo principal para entregar al cliente:
  output\SistemaSolares_Setup_1.0.0_10.exe

Contenido de la carpeta:
  setup.iss
    Script de Inno Setup usado para compilar el instalador.

  output\SistemaSolares_Setup_1.0.0_10.exe
    Instalador final compilado.

  output\BUILD_MANIFEST.txt
    Manifiesto con la version, rutas usadas y archivos incluidos del bundle Flutter.

  redist\VC_redist.x64.exe
    Microsoft Visual C++ Runtime incluido para instalacion si falta en Windows.

  redist\MicrosoftEdgeWebView2RuntimeInstallerX64.exe
    Runtime WebView2 guardado como recurso opcional. El instalador actual no lo instala
    porque la app local no lo requiere en este build.

  scripts\build_release_installer.ps1
    Script para regenerar release + instalador desde la raiz del proyecto.

  scripts\windows_release.ps1
    Wrapper de compatibilidad para regenerar el instalador.

Comando recomendado desde la raiz del proyecto:
  powershell -ExecutionPolicy Bypass -File .\tools\scripts\build_release_installer.ps1 -SkipAnalyze

El instalador instala:
  - sistema_solares.exe
  - flutter_windows.dll
  - DLLs de plugins Windows
  - sqlite3.dll
  - pdfium.dll
  - carpeta data completa
  - assets, fuentes y shaders Flutter
  - VC_redist.x64.exe como runtime requerido
