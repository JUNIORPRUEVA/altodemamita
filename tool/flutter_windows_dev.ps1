[CmdletBinding(PositionalBinding = $false)]
param(
  [switch]$SkipClean,
  [ValidateSet('run', 'test', 'build', 'clean', 'pub')]
  [string]$Command,
  [string]$Device = 'windows',
  [switch]$FlutterVerbose,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArgs
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$projectRootItem = Get-Item -LiteralPath $projectRoot
$resolvedProjectRoot = if ($projectRootItem.LinkType -eq 'Junction' -and $projectRootItem.Target) {
  try {
    (Get-Item -LiteralPath @($projectRootItem.Target)[0] -ErrorAction Stop).FullName
  } catch {
    @($projectRootItem.Target)[0]
  }
} else {
  $projectRootItem.FullName
}
$asciiRoot = 'C:\dev\sistema_solares_ascii'
$asciiParent = Split-Path -Parent $asciiRoot
$nativeAssetsDir = Join-Path $asciiRoot 'build\native_assets\windows'
$sqliteCacheRoot = Join-Path $asciiRoot '.dart_tool\hooks_runner\shared\sqlite3\build'
$ephemeralDir = Join-Path $asciiRoot 'windows\flutter\ephemeral'
$wrapperDir = Join-Path $ephemeralDir 'cpp_client_wrapper'
$flutterSdkRoot = $env:FLUTTER_ROOT

if (-not $flutterSdkRoot -or -not (Test-Path $flutterSdkRoot)) {
  $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
  if ($flutterCommand) {
    $flutterSdkRoot = Split-Path -Parent (Split-Path -Parent $flutterCommand.Source)
  }
}

$wrapperFallbackDir = if ($flutterSdkRoot) {
  Join-Path $flutterSdkRoot 'bin\cache\artifacts\engine\windows-x64\cpp_client_wrapper'
} else {
  $null
}
$sqliteFallbackPaths = @(
  (Join-Path $asciiRoot 'build\native_assets\windows\sqlite3.dll'),
  (Join-Path $asciiRoot 'build\windows\x64\runner\Debug\sqlite3.dll'),
  (Join-Path $asciiRoot 'build\windows\x64\runner\Release\sqlite3.dll'),
  (Join-Path $asciiRoot 'build\windows\x64\runner\Profile\sqlite3.dll')
)

if (-not (Test-Path $asciiParent)) {
  New-Item -ItemType Directory -Path $asciiParent | Out-Null
}

$junction = Get-Item -LiteralPath $asciiRoot -Force -ErrorAction SilentlyContinue
if ($null -eq $junction) {
  New-Item -ItemType Junction -Path $asciiRoot -Target $projectRoot | Out-Null
} elseif ($junction.LinkType -ne 'Junction') {
  throw "La ruta $asciiRoot ya existe y no es un junction administrado por este script."
} else {
  $junctionTarget = @($junction.Target)[0]
  $resolvedJunctionTarget = $junctionTarget

  if ($junctionTarget) {
    try {
      $resolvedJunctionTarget = (Get-Item -LiteralPath $junctionTarget -ErrorAction Stop).FullName
    } catch {
      $resolvedJunctionTarget = $junctionTarget
    }
  }

  if (-not $resolvedJunctionTarget -or $resolvedJunctionTarget -ine $resolvedProjectRoot) {
    Remove-Item -LiteralPath $asciiRoot -Force
    New-Item -ItemType Junction -Path $asciiRoot -Target $projectRoot | Out-Null
  }
}

Set-Location $asciiRoot

if ($env:DEV_SCRIPT_DEBUG -eq '1') {
  Write-Host "[DEV_SCRIPT] SkipClean=$SkipClean" -ForegroundColor DarkGray
  Write-Host "[DEV_SCRIPT] Command=$Command" -ForegroundColor DarkGray
  Write-Host "[DEV_SCRIPT] Device=$Device" -ForegroundColor DarkGray
  Write-Host "[DEV_SCRIPT] FlutterVerbose=$FlutterVerbose" -ForegroundColor DarkGray
  Write-Host "[DEV_SCRIPT] RawFlutterArgs=$($FlutterArgs -join ' ')" -ForegroundColor DarkGray
}

if (-not $SkipClean) {
  Remove-Item '.\build\native_assets\windows' -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item '.\build\windows' -Recurse -Force -ErrorAction SilentlyContinue
}

$plannedCommand = if ($Command) {
  $Command
} elseif ($FlutterArgs -and $FlutterArgs.Count -gt 0 -and $FlutterArgs[0] -in @('run', 'test', 'build', 'clean', 'pub')) {
  $FlutterArgs[0]
} else {
  'run'
}

# Some generated Windows install scripts expect this directory to exist even
# when there are no native assets to copy.
if (-not (Test-Path $nativeAssetsDir)) {
  New-Item -ItemType Directory -Path $nativeAssetsDir -Force | Out-Null
}

# Ensure sqlite3.dll is available for sqflite_common_ffi at runtime.
# The Flutter CMake install step copies everything under build/native_assets/windows
# next to the runner executable. If sqlite3.dll is missing there, startup will fail
# with error 126 (module not found).
$sqliteDestination = Join-Path $nativeAssetsDir 'sqlite3.dll'
if ($plannedCommand -eq 'test') {
  # Flutter's native asset installer will place sqlite3.dll in this folder.
  # If we pre-create it, some Flutter versions crash with errno 183.
  if (Test-Path $sqliteDestination) {
    try {
      Remove-Item -LiteralPath $sqliteDestination -Force -ErrorAction Stop
    } catch {
      Get-Process sistema_solares -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

      try {
        Remove-Item -LiteralPath $sqliteDestination -Force -ErrorAction Stop
      } catch {
        $backupName = "sqlite3.dll.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        try {
          Rename-Item -LiteralPath $sqliteDestination -NewName $backupName -Force -ErrorAction Stop
        } catch {
          Write-Error "No se pudo eliminar sqlite3.dll en $nativeAssetsDir (probablemente está bloqueado por una app en ejecución). Cierra la app y vuelve a ejecutar el task de tests."
          exit 1
        }
      }
    }
  }
} else {
  # For `run`/`build`, Flutter will install native assets and copy sqlite3.dll into
  # build/native_assets/windows. If the destination file already exists, some
  # Flutter versions fail with errno 183 (PathExistsException).
  if (Test-Path $sqliteDestination) {
    try {
      Remove-Item -LiteralPath $sqliteDestination -Force -ErrorAction Stop
    } catch {
      Get-Process sistema_solares -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

      try {
        Remove-Item -LiteralPath $sqliteDestination -Force -ErrorAction Stop
      } catch {
        $backupName = "sqlite3.dll.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        try {
          Rename-Item -LiteralPath $sqliteDestination -NewName $backupName -Force -ErrorAction Stop
        } catch {
          Write-Error "No se pudo eliminar sqlite3.dll en $nativeAssetsDir (probablemente está bloqueado por una app en ejecución). Cierra la app y vuelve a ejecutar el task de run."
          exit 1
        }
      }
    }
  }
}

# Help Dart VM tests and tools find sqlite3.dll too.
if (Test-Path (Join-Path $asciiRoot '.dart_tool\lib')) {
  $env:PATH = "$(Join-Path $asciiRoot '.dart_tool\lib');$env:PATH"
}
$env:PATH = "$nativeAssetsDir;$env:PATH"

if ($wrapperFallbackDir -and (Test-Path $wrapperFallbackDir)) {
  $requiredWrapperFiles = @(
    'core_implementations.cc',
    'standard_codec.cc',
    'flutter_engine.cc',
    'flutter_view_controller.cc',
    'plugin_registrar.cc'
  )

  $missingWrapperFiles = $requiredWrapperFiles | Where-Object {
    -not (Test-Path (Join-Path $wrapperDir $_))
  }

  if ($missingWrapperFiles.Count -gt 0) {
    New-Item -ItemType Directory -Path $wrapperDir -Force | Out-Null

    foreach ($wrapperFile in $requiredWrapperFiles) {
      Copy-Item (Join-Path $wrapperFallbackDir $wrapperFile) (Join-Path $wrapperDir $wrapperFile) -Force
    }

    if (-not (Test-Path (Join-Path $wrapperDir 'include')) -and (Test-Path (Join-Path $wrapperFallbackDir 'include'))) {
      Copy-Item (Join-Path $wrapperFallbackDir 'include') (Join-Path $wrapperDir 'include') -Recurse -Force
    }
  }
}

$effectiveArgs = @()

if ($Command) {
  $effectiveArgs += $Command
} elseif ($FlutterArgs -and $FlutterArgs.Count -gt 0 -and $FlutterArgs[0] -in @('run', 'test', 'build', 'clean', 'pub')) {
  $effectiveArgs += $FlutterArgs[0]
  $FlutterArgs = $FlutterArgs[1..($FlutterArgs.Count - 1)]
} else {
  $effectiveArgs += 'run'
}

if ($effectiveArgs[0] -eq 'run') {
  $effectiveArgs += @('-d', $Device)
}

if ($FlutterVerbose) {
  $effectiveArgs += '-v'
}

if ($FlutterArgs -and $FlutterArgs.Count -gt 0) {
  $effectiveArgs += $FlutterArgs
}

# Stabilize Flutter tests on Windows by default.
# Many tests use shared singletons / filesystem resources that can be flaky
# when the test runner executes in parallel.
if ($effectiveArgs[0] -eq 'test') {
  $hasConcurrency = $false
  foreach ($arg in $effectiveArgs) {
    if ($arg -match '^--concurrency(=|$)') {
      $hasConcurrency = $true
      break
    }
  }
  if (-not $hasConcurrency) {
    $effectiveArgs += '--concurrency=1'
  }
}

if ($env:DEV_SCRIPT_DEBUG -eq '1') {
  Write-Host "[DEV_SCRIPT] EffectiveFlutterArgs=$($effectiveArgs -join ' ')" -ForegroundColor DarkGray
}

& flutter @effectiveArgs
exit $LASTEXITCODE