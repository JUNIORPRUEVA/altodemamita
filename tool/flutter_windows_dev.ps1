param(
  [switch]$SkipClean,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArgs
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$resolvedProjectRoot = (Get-Item -LiteralPath $projectRoot).FullName
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

if (-not $SkipClean) {
  Remove-Item '.\build\native_assets\windows' -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item '.\build\windows' -Recurse -Force -ErrorAction SilentlyContinue
}

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

$sqliteDll = Get-ChildItem $sqliteCacheRoot -Recurse -Filter 'sqlite3.dll' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTimeUtc -Descending |
  Select-Object -First 1

if ($null -eq $sqliteDll) {
  foreach ($candidatePath in $sqliteFallbackPaths) {
    if (Test-Path $candidatePath) {
      $sqliteDll = Get-Item $candidatePath
      break
    }
  }
}

if ($null -eq $sqliteDll) {
  throw 'No se encontro sqlite3.dll ni en .dart_tool/hooks_runner/shared/sqlite3/build ni en las rutas de salida conocidas de Windows.'
}

New-Item -ItemType Directory -Path $nativeAssetsDir -Force | Out-Null

$sqliteDestination = Join-Path $nativeAssetsDir 'sqlite3.dll'
$sqliteCopied = $false

for ($attempt = 1; $attempt -le 10 -and -not $sqliteCopied; $attempt++) {
  try {
    if (Test-Path $sqliteDestination) {
      Remove-Item $sqliteDestination -Force -ErrorAction Stop
    }

    Copy-Item $sqliteDll.FullName $sqliteDestination -Force -ErrorAction Stop
    $sqliteCopied = $true
  } catch {
    if ($attempt -eq 10) {
      throw
    }

    Start-Sleep -Milliseconds 500
  }
}

if (-not $FlutterArgs -or $FlutterArgs.Count -eq 0) {
  $FlutterArgs = @('run', '-d', 'windows')
}

& flutter @FlutterArgs
exit $LASTEXITCODE