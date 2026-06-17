@echo off
REM ============================================================
REM Reset InitialCloudUpload flag
REM ============================================================
REM
REM Este script resetea la bandera de sincronización inicial
REM (InitialCloudUpload) para que se ejecute de nuevo al abrir
REM app_local.
REM
REM La bandera se guarda en SharedPreferences de Windows:
REM   %APPDATA%/com.example.sistema_solares/flutter_shared_preferences.json
REM
REM Claves que se resetean:
REM   sync.local_upload_bootstrap_completed
REM   sync.local_upload_bootstrap_completed_at
REM   sync.local_upload_bootstrap_backend_url
REM   sync.local_upload_bootstrap_version
REM
REM Uso:
REM   tools\scripts\reset_initial_cloud_upload_flag.bat
REM
REM ============================================================

setlocal enabledelayedexpansion

set "PREFS_FILE=%APPDATA%\com.example.sistema_solares\flutter_shared_preferences.json"

if not exist "%PREFS_FILE%" (
    echo [INFO] No se encontro el archivo de preferencias en:
    echo       %PREFS_FILE%
    echo.
    echo       Esto es normal si la app nunca se ha ejecutado.
    echo       No es necesario resetear nada.
    exit /b 0
)

echo [INFO] Archivo de preferencias encontrado: %PREFS_FILE%
echo [INFO] Creando backup...

copy "%PREFS_FILE%" "%PREFS_FILE%.backup" > nul
echo [INFO] Backup creado: %PREFS_FILE%.backup

echo [INFO] Resetando banderas de InitialCloudUpload...

REM Usamos PowerShell para modificar el JSON de forma segura
powershell -Command ^
    "$json = Get-Content '%PREFS_FILE%' -Raw | ConvertFrom-Json; " ^
    "$removed = $false; " ^
    "if ($json.PSObject.Properties.Name -contains 'sync.local_upload_bootstrap_completed') { " ^
    "    $json.PSObject.Properties.Remove('sync.local_upload_bootstrap_completed'); " ^
    "    $removed = $true; " ^
    "}; " ^
    "if ($json.PSObject.Properties.Name -contains 'sync.local_upload_bootstrap_completed_at') { " ^
    "    $json.PSObject.Properties.Remove('sync.local_upload_bootstrap_completed_at'); " ^
    "    $removed = $true; " ^
    "}; " ^
    "if ($json.PSObject.Properties.Name -contains 'sync.local_upload_bootstrap_backend_url') { " ^
    "    $json.PSObject.Properties.Remove('sync.local_upload_bootstrap_backend_url'); " ^
    "    $removed = $true; " ^
    "}; " ^
    "if ($json.PSObject.Properties.Name -contains 'sync.local_upload_bootstrap_version') { " ^
    "    $json.PSObject.Properties.Remove('sync.local_upload_bootstrap_version'); " ^
    "    $removed = $true; " ^
    "}; " ^
    "if ($removed) { " ^
    "    $json | ConvertTo-Json -Depth 10 | Set-Content '%PREFS_FILE%' -Encoding UTF8; " ^
    "    Write-Host '[OK] Banderas reseteadas correctamente.'; " ^
    "} else { " ^
    "    Write-Host '[INFO] No se encontraron banderas para resetear (ya estaban limpias).'; " ^
    "}"

echo.
echo [INFO] Hecho. Al abrir app_local, deberias ver:
echo       [InitialCloudUpload] starting
echo       [InitialCloudUpload] backend online
echo       [InitialCloudUpload] completed
echo.
echo Para restaurar el backup si algo sale mal:
echo   copy "%PREFS_FILE%.backup" "%PREFS_FILE%"
echo.

endlocal
