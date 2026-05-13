<# 
 Build and generate Windows installer for Sistema Solares
 Version: 2.0
 Purpose: Complete release build with installer generation
#>

param(
    [string]$Version = "1.0.0+1",
    [string]$VersionInfo = "1.0.0.1",
    [switch]$SkipFlutterBuild = $false,
    [switch]$SkipAnalyze = $false
)

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$BackendDir = Join-Path $ProjectRoot "backend"
$InstallerDir = Join-Path $ProjectRoot "installer"
$BuildDir = Join-Path $ProjectRoot "build"
$SourceDir = Join-Path $BuildDir "windows" "runner" "Release"

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "🚀 Sistema Solares - Release Build & Installer Generator" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Version: $Version" -ForegroundColor Yellow
Write-Host "VersionInfo: $VersionInfo" -ForegroundColor Yellow
Write-Host "ProjectRoot: $ProjectRoot" -ForegroundColor Gray
Write-Host ""

# Step 1: Backend Build Validation
Write-Host "📦 STEP 1: Validating Backend Build..." -ForegroundColor Cyan
Push-Location $BackendDir
try {
    $buildResult = npm.cmd run build 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Backend build failed!" -ForegroundColor Red
        Write-Host $buildResult
        exit 1
    }
    Write-Host "✅ Backend build successful" -ForegroundColor Green
} finally {
    Pop-Location
}

# Step 2: Dart Analysis
if (-not $SkipAnalyze) {
    Write-Host ""
    Write-Host "🔍 STEP 2: Running Dart Analysis..." -ForegroundColor Cyan
    Push-Location $ProjectRoot
    try {
        $analyzeResult = flutter analyze 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "⚠️  Analysis warnings detected (non-fatal)" -ForegroundColor Yellow
        } else {
            Write-Host "✅ No analysis issues" -ForegroundColor Green
        }
    } finally {
        Pop-Location
    }
}

# Step 3: Flutter Windows Release Build
if (-not $SkipFlutterBuild) {
    Write-Host ""
    Write-Host "🔨 STEP 3: Building Flutter Windows Release..." -ForegroundColor Cyan
    Push-Location $ProjectRoot
    try {
        Write-Host "   Cleaning previous builds..." -ForegroundColor Gray
        flutter clean -q 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        
        Write-Host "   Compiling release executable..." -ForegroundColor Gray
        $buildResult = flutter build windows --release -q 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Flutter build failed!" -ForegroundColor Red
            Write-Host $buildResult
            exit 1
        }
        
        Write-Host "✅ Flutter release build successful" -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

# Step 4: Verify Executable
Write-Host ""
Write-Host "🔎 STEP 4: Verifying Executable..." -ForegroundColor Cyan
$exePath = Join-Path $SourceDir "sistema_solares.exe"
if (Test-Path $exePath) {
    $fileSize = (Get-Item $exePath).Length / 1MB
    Write-Host "✅ Executable found: $exePath" -ForegroundColor Green
    Write-Host "   Size: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Gray
} else {
    Write-Host "❌ Executable not found at: $exePath" -ForegroundColor Red
    exit 1
}

# Step 5: Generate Installer
Write-Host ""
Write-Host "📋 STEP 5: Generating Windows Installer..." -ForegroundColor Cyan

$setupFile = Join-Path $InstallerDir "setup.iss"
if (-not (Test-Path $setupFile)) {
    Write-Host "❌ Installer script not found: $setupFile" -ForegroundColor Red
    exit 1
}

$outputDir = Join-Path $InstallerDir "output"
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Find Inno Setup compiler
$innoSetupPaths = @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 5\ISCC.exe",
    "C:\Program Files\Inno Setup 5\ISCC.exe"
)

$innoCompiler = $null
foreach ($path in $innoSetupPaths) {
    if (Test-Path $path) {
        $innoCompiler = $path
        break
    }
}

if (-not $innoCompiler) {
    Write-Host "⚠️  Inno Setup compiler not found. Manual build required." -ForegroundColor Yellow
    Write-Host "   Expected paths:" -ForegroundColor Gray
    $innoSetupPaths | ForEach-Object { Write-Host "   - $_" -ForegroundColor Gray }
    Write-Host ""
    Write-Host "   Install from: https://jrsoftware.org/isdl.php" -ForegroundColor Yellow
} else {
    Write-Host "   Using Inno Setup: $innoCompiler" -ForegroundColor Gray
    
    try {
        $outputExe = Join-Path $outputDir "SistemaSolares_$Version.exe"
        $params = @(
            "`"$setupFile`"",
            "/DMyAppVersion=$Version",
            "/DMyAppVersionInfo=$VersionInfo",
            "/O`"$(Join-Path $outputDir '')`""
        )
        
        Write-Host "   Compiling installer..." -ForegroundColor Gray
        & $innoCompiler @params
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Installer generated successfully" -ForegroundColor Green
            
            # Find generated installer
            $generatedInstallers = Get-ChildItem $outputDir -Filter "*.exe" | Sort-Object LastWriteTime -Descending
            if ($generatedInstallers.Count -gt 0) {
                $installer = $generatedInstallers[0]
                $installerSize = $installer.Length / 1MB
                Write-Host "   Installer: $($installer.FullName)" -ForegroundColor Green
                Write-Host "   Size: $([math]::Round($installerSize, 2)) MB" -ForegroundColor Gray
            }
        } else {
            Write-Host "❌ Installer compilation failed" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "❌ Error running Inno Setup: $_" -ForegroundColor Red
        exit 1
    }
}

# Summary
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "✅ BUILD COMPLETE" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "📊 Artifacts:" -ForegroundColor Yellow
Write-Host "   Executable: $exePath" -ForegroundColor White
Write-Host "   Installer output: $outputDir" -ForegroundColor White
Write-Host ""
Write-Host "⚡ Next Steps:" -ForegroundColor Yellow
Write-Host "   1. Test the executable: $exePath" -ForegroundColor White
Write-Host "   2. Distribute installer from: $outputDir" -ForegroundColor White
Write-Host ""
Write-Host "🔗 Version Info:" -ForegroundColor Yellow
Write-Host "   App Version: $Version" -ForegroundColor White
Write-Host "   File Version: $VersionInfo" -ForegroundColor White
Write-Host ""
