<#
  Build and generate the Windows installer for app_local.

  Output:
    app_local/instalacion/output/SistemaSolares_Setup_<version>_<build>.exe
    app_local/instalacion/output/BUILD_MANIFEST.txt
#>

param(
  [string]$Version = "",
  [string]$VersionInfo = "",
  [switch]$SkipFlutterBuild = $false,
  [switch]$SkipAnalyze = $false,
  [switch]$PerUserInstaller = $false,
  [switch]$IncludeWebView2Runtime = $false,
  [string]$SyncApiBaseUrl = "https://altodemanita-altodemamita-backent.onqyr1.easypanel.host"
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$AppDir = Join-Path $ProjectRoot 'app_local'
$InstallerDir = Join-Path $AppDir 'instalacion'
$SetupFile = Join-Path $InstallerDir 'setup.iss'
$OutputDir = Join-Path $InstallerDir 'output'
$ReleaseDir = Join-Path $AppDir 'build\windows\x64\runner\Release'
$ReleaseExe = Join-Path $ReleaseDir 'sistema_solares.exe'
$PubspecPath = Join-Path $AppDir 'pubspec.yaml'
$VcRedistPath = Join-Path $InstallerDir 'redist\VC_redist.x64.exe'
$WebView2Path = Join-Path $InstallerDir 'redist\MicrosoftEdgeWebView2RuntimeInstallerX64.exe'

function Get-PubspecVersion {
  param([string]$Path)

  $versionLine = Select-String -Path $Path -Pattern '^version:\s*(.+)$' | Select-Object -First 1
  if ($null -eq $versionLine) {
    throw "No version line was found in $Path."
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
  param(
    [string]$BuildName,
    [string]$BuildNumber
  )

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
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 5\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 5\ISCC.exe')
  ) | Where-Object { $_ -and (Test-Path $_) }

  if ($candidates.Count -gt 0) {
    return @($candidates)[0]
  }

  return $null
}

if (-not (Test-Path $AppDir)) {
  throw "app_local was not found at $AppDir."
}
if (-not (Test-Path $SetupFile)) {
  throw "Inno Setup script was not found at $SetupFile."
}
if (-not (Test-Path $VcRedistPath)) {
  throw "Required Visual C++ redistributable was not found at $VcRedistPath."
}
if ($IncludeWebView2Runtime -and -not (Test-Path $WebView2Path)) {
  throw "WebView2 runtime was requested but not found at $WebView2Path."
}

$AppVersion = if ($Version.Trim()) { $Version.Trim() } else { Get-PubspecVersion -Path $PubspecPath }
$VersionParts = Get-VersionParts -AppVersion $AppVersion
$ResolvedVersionInfo = if ($VersionInfo.Trim()) {
  $VersionInfo.Trim()
} else {
  Convert-ToVersionInfo -BuildName $VersionParts.BuildName -BuildNumber $VersionParts.BuildNumber
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

Write-Host '==============================================================='
Write-Host 'Sistema Solares - app_local Windows installer'
Write-Host '==============================================================='
Write-Host "Project root: $ProjectRoot"
Write-Host "App dir:      $AppDir"
Write-Host "Installer:    $SetupFile"
Write-Host "Output dir:   $OutputDir"
Write-Host "Version:      $AppVersion"
Write-Host "VersionInfo:  $ResolvedVersionInfo"
Write-Host "Sync API URL: $SyncApiBaseUrl"
Write-Host ''

if (-not $SkipAnalyze) {
  Write-Host '[1/4] Running flutter analyze...'
  Push-Location $AppDir
  try {
    & flutter analyze
  } finally {
    Pop-Location
  }
}

if (-not $SkipFlutterBuild) {
  Write-Host '[2/4] Building Flutter Windows release...'
  Push-Location $AppDir
  try {
    & flutter build windows --release --dart-define=SYNC_API_BASE_URL=$SyncApiBaseUrl --build-name $VersionParts.BuildName --build-number $VersionParts.BuildNumber
  } finally {
    Pop-Location
  }
} else {
  Write-Host '[2/4] Skipping Flutter build.'
}

Write-Host '[3/4] Verifying release bundle...'
if (-not (Test-Path $ReleaseExe)) {
  throw "Release executable was not found at $ReleaseExe."
}

$requiredBundleItems = @(
  $ReleaseExe,
  (Join-Path $ReleaseDir 'flutter_windows.dll'),
  (Join-Path $ReleaseDir 'data\icudtl.dat'),
  (Join-Path $ReleaseDir 'data\flutter_assets\AssetManifest.bin')
)
$missingBundleItems = @($requiredBundleItems | Where-Object { -not (Test-Path $_) })
if ($missingBundleItems.Count -gt 0) {
  throw "The Flutter release bundle is incomplete:`n - $($missingBundleItems -join "`n - ")"
}

$IsccPath = Resolve-IsccPath
if (-not $IsccPath) {
  throw 'ISCC.exe was not found. Install Inno Setup 6 or add ISCC.exe to PATH.'
}

Write-Host '[4/4] Compiling Inno Setup installer...'
$isccArgs = @(
  $SetupFile,
  "/DMyAppVersion=$AppVersion",
  "/DMyAppVersionInfo=$ResolvedVersionInfo",
  "/DMyAppSourceDir=$ReleaseDir"
)

if ($PerUserInstaller) {
  $isccArgs += '/DInstallPerUser=1'
}
if ($IncludeWebView2Runtime) {
  $isccArgs += '/DIncludeWebView2Runtime=1'
}

& $IsccPath @isccArgs
if ($LASTEXITCODE -ne 0) {
  throw "Inno Setup failed with exit code $LASTEXITCODE."
}

$generatedInstaller = Get-ChildItem $OutputDir -Filter '*.exe' |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $generatedInstaller) {
  throw "No installer executable was produced in $OutputDir."
}

$manifestPath = Join-Path $OutputDir 'BUILD_MANIFEST.txt'
$installerSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $generatedInstaller.FullName).Hash
$diagnosticsLogPath = '%LOCALAPPDATA%\SistemaSolares\logs\sync_diagnostics.log'
$bundleFiles = Get-ChildItem $ReleaseDir -Recurse -File |
  ForEach-Object { $_.FullName.Substring($ReleaseDir.Length + 1) } |
  Sort-Object

$manifest = @(
  'Sistema Solares installer build manifest',
  "GeneratedAt: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
  "ProjectRoot: $ProjectRoot",
  "AppDir: $AppDir",
  "ReleaseDir: $ReleaseDir",
  "InstallerScript: $SetupFile",
  "InstallerExe: $($generatedInstaller.FullName)",
  "InstallerSHA256: $installerSha256",
  "Version: $AppVersion",
  "VersionInfo: $ResolvedVersionInfo",
  "SyncApiBaseUrl: $SyncApiBaseUrl",
  "DiagnosticsLogPath: $diagnosticsLogPath",
  "PerUserInstaller: $PerUserInstaller",
  "IncludeWebView2Runtime: $IncludeWebView2Runtime",
  '',
  'Release bundle files:',
  ($bundleFiles | ForEach-Object { " - $_" })
)
$manifest | Set-Content -Path $manifestPath -Encoding UTF8

Write-Host ''
Write-Host 'Build complete.'
Write-Host "Installer: $($generatedInstaller.FullName)"
Write-Host "Manifest:  $manifestPath"
