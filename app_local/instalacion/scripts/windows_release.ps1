param(
  [switch]$Build,
  [switch]$CompileInstaller,
  [switch]$PerUserInstaller,
  [switch]$SkipAnalyze,
  [string]$Version
)

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'build_release_installer.ps1'
if (-not (Test-Path $scriptPath)) {
  throw "No se encontro $scriptPath."
}

if (-not $Build -and -not $CompileInstaller) {
  Write-Host 'Preparacion del instalador de app_local.'
  Write-Host 'Para generar todo:'
  Write-Host '  powershell -ExecutionPolicy Bypass -File .\tools\scripts\windows_release.ps1 -Build -CompileInstaller'
  return
}

$forwardArgs = @()
if ($Version) {
  $forwardArgs += @('-Version', $Version)
}
if ($SkipAnalyze) {
  $forwardArgs += '-SkipAnalyze'
}
if ($PerUserInstaller) {
  $forwardArgs += '-PerUserInstaller'
}
if (-not $Build) {
  $forwardArgs += '-SkipFlutterBuild'
}

& $scriptPath @forwardArgs
