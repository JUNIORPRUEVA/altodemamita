# Setup script for VS Code hot-reload launch (no flutter run)
# Ensures junction, cpp_client_wrapper and sqlite3.dll are in place.

$ErrorActionPreference = 'Stop'

$projectRoot     = Split-Path -Parent $PSScriptRoot
$resolvedRoot    = (Get-Item -LiteralPath $projectRoot).FullName
$asciiRoot       = 'C:\dev\sistema_solares_ascii'
$asciiParent     = Split-Path -Parent $asciiRoot
$nativeAssetsDir = Join-Path $asciiRoot 'build\native_assets\windows'
$sqliteCacheRoot = Join-Path $asciiRoot '.dart_tool\hooks_runner\shared\sqlite3\build'
$wrapperDir      = Join-Path $asciiRoot 'windows\flutter\ephemeral\cpp_client_wrapper'

$sqliteFallbackPaths = @(
  (Join-Path $asciiRoot 'build\native_assets\windows\sqlite3.dll'),
  (Join-Path $asciiRoot 'build\windows\x64\runner\Debug\sqlite3.dll'),
  (Join-Path $asciiRoot 'build\windows\x64\runner\Release\sqlite3.dll')
)

# ── 1. Flutter SDK root ─────────────────────────────────────────────────────
$flutterSdkRoot = $env:FLUTTER_ROOT
if (-not $flutterSdkRoot -or -not (Test-Path $flutterSdkRoot)) {
  $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
  if ($flutterCmd) {
    $flutterSdkRoot = Split-Path -Parent (Split-Path -Parent $flutterCmd.Source)
  }
}

$wrapperFallbackDir = if ($flutterSdkRoot) {
  Join-Path $flutterSdkRoot 'bin\cache\artifacts\engine\windows-x64\cpp_client_wrapper'
} else { $null }

# ── 2. Junction ─────────────────────────────────────────────────────────────
if (-not (Test-Path $asciiParent)) {
  New-Item -ItemType Directory -Path $asciiParent | Out-Null
}

$junction = Get-Item -LiteralPath $asciiRoot -Force -ErrorAction SilentlyContinue
if ($null -eq $junction) {
  New-Item -ItemType Junction -Path $asciiRoot -Target $projectRoot | Out-Null
  Write-Host "[setup] Junction creado: $asciiRoot -> $projectRoot"
} else {
  $target = @($junction.Target)[0]
  try { $target = (Get-Item -LiteralPath $target -ErrorAction Stop).FullName } catch {}
  if ($target -ine $resolvedRoot) {
    Remove-Item -LiteralPath $asciiRoot -Force
    New-Item -ItemType Junction -Path $asciiRoot -Target $projectRoot | Out-Null
    Write-Host "[setup] Junction actualizado: $asciiRoot -> $projectRoot"
  } else {
    Write-Host "[setup] Junction OK"
  }
}

Set-Location $asciiRoot

# ── 3. cpp_client_wrapper ────────────────────────────────────────────────────
if ($wrapperFallbackDir -and (Test-Path $wrapperFallbackDir)) {
  $required = @(
    'core_implementations.cc',
    'flutter_engine.cc',
    'flutter_view_controller.cc',
    'plugin_registrar.cc',
    'standard_codec.cc'
  )
  $updated = 0

  New-Item -ItemType Directory -Path $wrapperDir -Force | Out-Null
  foreach ($f in $required) {
    $source = Join-Path $wrapperFallbackDir $f
    $dest = Join-Path $wrapperDir $f

    if (Test-Path $source) {
      Copy-Item $source $dest -Force
      $updated++
    }
  }

  $includeSource = Join-Path $wrapperFallbackDir 'include'
  $includeDest   = Join-Path $wrapperDir 'include'
  if (Test-Path $includeSource) {
    Copy-Item $includeSource $includeDest -Recurse -Force
  }

  $missingAfterSync = $required | Where-Object { -not (Test-Path (Join-Path $wrapperDir $_)) }
  if ($missingAfterSync.Count -gt 0) {
    throw "[setup] cpp_client_wrapper incompleto despues de sincronizar: $($missingAfterSync -join ', ')"
  }

  Write-Host "[setup] cpp_client_wrapper sincronizado ($updated archivos)"
} else {
  Write-Host "[setup] WARN: no se encontro wrapperFallbackDir, se omite copia"
}

# ── 4. sqlite3.dll ───────────────────────────────────────────────────────────
$sqliteDll = Get-ChildItem $sqliteCacheRoot -Recurse -Filter 'sqlite3.dll' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1

if ($null -eq $sqliteDll) {
  foreach ($p in $sqliteFallbackPaths) {
    if (Test-Path $p) { $sqliteDll = Get-Item $p; break }
  }
}

if ($null -ne $sqliteDll) {
  New-Item -ItemType Directory -Path $nativeAssetsDir -Force | Out-Null
  $dest = Join-Path $nativeAssetsDir 'sqlite3.dll'
  for ($i = 1; $i -le 5; $i++) {
    try {
      if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction Stop }
      Copy-Item $sqliteDll.FullName $dest -Force -ErrorAction Stop
      Write-Host "[setup] sqlite3.dll copiado"
      break
    } catch {
      if ($i -eq 5) { Write-Host "[setup] WARN: no se pudo copiar sqlite3.dll: $_" }
      else { Start-Sleep -Milliseconds 400 }
    }
  }
} else {
  Write-Host "[setup] WARN: sqlite3.dll no encontrado, flutter run podria fallar"
}

Write-Host "[setup] Listo. VS Code puede lanzar ahora."
