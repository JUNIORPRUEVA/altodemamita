param(
  [switch]$Build,
  [switch]$CompileInstaller,
  [switch]$PerUserInstaller,
  [switch]$SkipSetup,
  [string]$Version
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$setupScript = Join-Path $projectRoot 'installer\setup.iss'
$setupHelper = Join-Path $PSScriptRoot 'flutter_vscode_setup.ps1'
$outputDir = Join-Path $projectRoot 'installer\output'
$asciiRoot = 'C:\dev\sistema_solares_ascii'
$releaseDir = Join-Path $asciiRoot 'build\windows\x64\runner\Release'
$releaseExe = Join-Path $releaseDir 'sistema_solares.exe'

function Get-PubspecVersion {
  param([string]$Path)

  $versionLine = Select-String -Path $Path -Pattern '^version:\s*(.+)$' | Select-Object -First 1
  if ($null -eq $versionLine) {
    throw 'No se encontro la version en pubspec.yaml.'
  }

  return $versionLine.Matches[0].Groups[1].Value.Trim()
}

function Get-VersionParts {
  param([string]$AppVersion)

  $parts = $AppVersion -split '\+', 2
  $buildName = $parts[0]
  $buildNumber = if ($parts.Count -gt 1 -and $parts[1]) { $parts[1] } else { '1' }

  return [pscustomobject]@{
    BuildName = $buildName
    BuildNumber = $buildNumber
  }
}

function Convert-ToVersionInfo {
  param([string]$BuildName, [string]$BuildNumber)

  $segments = @($BuildName.Split('.') | Where-Object { $_ -ne '' })
  while ($segments.Count -lt 3) {
    $segments += '0'
  }

  if ($segments.Count -gt 3) {
    $segments = $segments[0..2]
  }

  return '{0}.{1}.{2}.{3}' -f $segments[0], $segments[1], $segments[2], $BuildNumber
}

function Resolve-IsccPath {
  $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
  ) | Where-Object { $_ -and (Test-Path $_) }

  if ($candidates.Count -gt 0) {
    return @($candidates)[0]
  }

  return $null
}

$appVersion = if ($Version) { $Version.Trim() } else { Get-PubspecVersion -Path $pubspecPath }
$versionParts = Get-VersionParts -AppVersion $appVersion
$versionInfo = Convert-ToVersionInfo -BuildName $versionParts.BuildName -BuildNumber $versionParts.BuildNumber

$requiredFiles = @(
  (Join-Path $projectRoot 'installer\setup.iss'),
  (Join-Path $projectRoot 'installer\redist\VC_redist.x64.exe'),
  (Join-Path $projectRoot 'windows\runner\resources\app_icon.ico')
)

$missingFiles = @($requiredFiles | Where-Object { -not (Test-Path $_) })
if ($missingFiles.Count -gt 0) {
  throw "Faltan archivos requeridos para el release:`n - $($missingFiles -join "`n - ")"
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

Write-Host "[release] Version app: $appVersion"
Write-Host "[release] Version build: $($versionParts.BuildName)"
Write-Host "[release] Build number: $($versionParts.BuildNumber)"
Write-Host "[release] VersionInfo: $versionInfo"
Write-Host "[release] Script Inno Setup: $setupScript"
Write-Host "[release] Salida instalador: $outputDir"
if ($PerUserInstaller) {
  Write-Host '[release] Modo instalador: por usuario, sin permisos de administrador'
}

if (-not $SkipSetup) {
  if (-not (Test-Path $setupHelper)) {
    throw 'No se encontro flutter_vscode_setup.ps1 para preparar la ruta ASCII.'
  }

  & $setupHelper
}

if (-not $Build -and -not $CompileInstaller) {
  Write-Host '[release] Preparacion completada. No se ha compilado nada.'
  Write-Host '[release] Cuando estes listo para generar el release:'
  Write-Host '  powershell -ExecutionPolicy Bypass -File .\tool\windows_release.ps1 -Build'
  Write-Host '  powershell -ExecutionPolicy Bypass -File .\tool\windows_release.ps1 -Build -CompileInstaller'
  return
}

if ($Build) {
  $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
  if (-not $flutterCommand) {
    throw 'Flutter no esta disponible en PATH.'
  }

  Push-Location $asciiRoot
  try {
    & $flutterCommand.Source 'build' 'windows' '--release' '--build-name' $versionParts.BuildName '--build-number' $versionParts.BuildNumber
  } finally {
    Pop-Location
  }
}

if ($CompileInstaller) {
  if (-not (Test-Path $releaseExe)) {
    throw "No existe el binario release esperado: $releaseExe"
  }

  $isccPath = Resolve-IsccPath
  if (-not $isccPath) {
    throw 'No se encontro ISCC.exe. Instala Inno Setup 6 o agrega ISCC.exe al PATH.'
  }

  $isccArgs = @(
    $setupScript,
    "/DMyAppVersion=$appVersion",
    "/DMyAppVersionInfo=$versionInfo",
    "/DMyAppSourceDir=$releaseDir"
  )

  if ($PerUserInstaller) {
    $isccArgs += '/DInstallPerUser=1'
  }

  & $isccPath @isccArgs
}