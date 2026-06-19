@echo off
setlocal

set "STAMP=%DATE:/=-%_%TIME::=-%"
set "STAMP=%STAMP: =_%"
set "OUTDIR=%USERPROFILE%\Desktop\SistemaSolares_Diagnostico_%STAMP%"
set "LOGDIR=%LOCALAPPDATA%\SistemaSolares\logs"
set "DBPATH=%LOCALAPPDATA%\SistemaSolares\data\database\sistema_solares.db"
set "PREFS=%APPDATA%\Sistema Solares\Sistema Solares\shared_preferences.json"

mkdir "%OUTDIR%" >nul 2>nul

if exist "%LOGDIR%\sync_diagnostics.log" (
  copy "%LOGDIR%\sync_diagnostics.log" "%OUTDIR%\sync_diagnostics.log" >nul
)

(
  echo Sistema Solares - Diagnostico de sincronizacion
  echo Fecha: %DATE% %TIME%
  echo Log: %LOGDIR%\sync_diagnostics.log
  echo DB local: %DBPATH%
  if exist "%DBPATH%" (
    for %%F in ("%DBPATH%") do (
      echo DB existe: si
      echo DB tamano bytes: %%~zF
      echo DB modificada: %%~tF
    )
  ) else (
    echo DB existe: no
  )
  echo.
  echo Preferencias bootstrap:
) > "%OUTDIR%\diagnostico.txt"

if exist "%PREFS%" (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$p='%PREFS%'; $j=Get-Content -Raw -LiteralPath $p | ConvertFrom-Json -AsHashtable; $j.GetEnumerator() | Where-Object { $_.Key -like '*local_upload_bootstrap*' -or $_.Key -eq 'flutter.sync.device_id' } | ForEach-Object { ('{0}={1}' -f $_.Key,$_.Value) }" ^
    >> "%OUTDIR%\diagnostico.txt"
)

where sqlite3 >nul 2>nul
if %ERRORLEVEL% EQU 0 if exist "%DBPATH%" (
  (
    echo.
    echo Conteos locales:
    sqlite3 "%DBPATH%" "SELECT 'clientes=' || COUNT(*) FROM clientes;"
    sqlite3 "%DBPATH%" "SELECT 'vendedores=' || COUNT(*) FROM vendedores;"
    sqlite3 "%DBPATH%" "SELECT 'solares=' || COUNT(*) FROM solares;"
    sqlite3 "%DBPATH%" "SELECT 'ventas=' || COUNT(*) FROM ventas;"
    sqlite3 "%DBPATH%" "SELECT 'cuotas=' || COUNT(*) FROM cuotas;"
    sqlite3 "%DBPATH%" "SELECT 'pagos=' || COUNT(*) FROM pagos;"
    sqlite3 "%DBPATH%" "SELECT 'sync_queue=' || COUNT(*) FROM sync_queue;"
  ) >> "%OUTDIR%\diagnostico.txt" 2>nul
)

echo Diagnostico creado en:
echo %OUTDIR%
endlocal
