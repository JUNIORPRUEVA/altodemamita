#requires -Version 5.1
<#
    FASE 06 — Lanzador de UAT para Windows (FAIL-CLOSED).

    Reglas:
      * Solo acepta un backend LOCAL (127.0.0.1 / localhost). Si la URL
        configurada apunta a produccion (easypanel, https remoto, IP publica),
        ABORTA y no arranca la aplicacion.
      * Usa un perfil de usuario aislado (LOCALAPPDATA propio) para no tocar
        los datos de la instalacion real del equipo.
      * Despues de arrancar, comprueba que TODAS las conexiones TCP del proceso
        van a 127.0.0.1. Si aparece una conexion externa, cierra la app y falla.
#>
param(
    [string]$ApiUrl = 'http://127.0.0.1:4111',
    [string]$ExePath = 'C:\src\ss-uat\sistema_solares.exe',
    [string]$ProfileDir = 'C:\src\ss-uat-profile',
    [int]$WaitSeconds = 12
)

$ErrorActionPreference = 'Stop'

function Fail([string]$message) {
    Write-Host "NO-GO: $message" -ForegroundColor Red
    exit 2
}

# --- 1. Guardia de entorno ------------------------------------------------
if ($ApiUrl -notmatch '^http://(127\.0\.0\.1|localhost):\d+$') {
    Fail "la URL '$ApiUrl' no es un backend local de aceptacion."
}
if ($ApiUrl -match 'easypanel|\.host|https://') {
    Fail "la URL '$ApiUrl' parece PRODUCCION. UAT cancelada."
}
if (-not (Test-Path $ExePath)) {
    Fail "no existe el ejecutable '$ExePath'."
}

$uri = [System.Uri]$ApiUrl
$port = $uri.Port
$healthy = $false
try {
    $response = Invoke-WebRequest -Uri "$ApiUrl/api/health" -TimeoutSec 5 -UseBasicParsing
    $healthy = $response.StatusCode -eq 200
} catch {
    $healthy = $false
}
if (-not $healthy) {
    Fail "el backend de aceptacion no responde en $ApiUrl (arrancalo antes)."
}
Write-Host "OK: backend de aceptacion responde en $ApiUrl" -ForegroundColor Green

# --- 2. Perfil aislado ----------------------------------------------------
if (-not (Test-Path $ProfileDir)) {
    New-Item -ItemType Directory -Path $ProfileDir | Out-Null
}
$env:LOCALAPPDATA = $ProfileDir
$env:APPDATA = Join-Path $ProfileDir 'Roaming'
if (-not (Test-Path $env:APPDATA)) {
    New-Item -ItemType Directory -Path $env:APPDATA | Out-Null
}
Write-Host "OK: perfil aislado LOCALSAPPDATA=$ProfileDir" -ForegroundColor Green

# --- 3. Arranque ----------------------------------------------------------
$process = Start-Process -FilePath $ExePath -PassThru
Write-Host "OK: iniciado PID=$($process.Id)" -ForegroundColor Green

Start-Sleep -Seconds $WaitSeconds
$process.Refresh()
if ($process.HasExited) {
    Fail "la aplicacion termino sola (codigo $($process.ExitCode))."
}

# --- 4. Verificacion de trafico (fail-closed) -----------------------------
$connections = Get-NetTCPConnection -OwningProcess $process.Id -ErrorAction SilentlyContinue
$established = @($connections | Where-Object { $_.State -eq 'Established' })
$external = @($established | Where-Object {
        $_.RemoteAddress -notin @('127.0.0.1', '::1', '0.0.0.0', '::')
    })

Write-Host ''
Write-Host "Conexiones establecidas del proceso:" -ForegroundColor Cyan
$established | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State |
    Format-Table -AutoSize | Out-String | Write-Host

if ($external.Count -gt 0) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    Fail "la aplicacion abrio conexiones FUERA de 127.0.0.1: $($external.RemoteAddress -join ', ')"
}

$toAcceptance = @($established | Where-Object { $_.RemotePort -eq $port })
Write-Host "Conexiones al backend de aceptacion ($port): $($toAcceptance.Count)" -ForegroundColor Green
Write-Host "TRAFFIC-CHECK: PASS (sin trafico externo)" -ForegroundColor Green
Write-Host "PID=$($process.Id)"
