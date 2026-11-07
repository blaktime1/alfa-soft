# ==============================================================================
# ALFA SOFT - Production Windows Release Build Script
# ==============================================================================

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " ALFA SOFT - Windows Desktop Native Release Compiler" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. Clean previous build artifacts
Write-Host "[1/4] Cleaning previous build artifacts..." -ForegroundColor Yellow
flutter clean

# 2. Get dependencies
Write-Host "[2/4] Resolving dependencies..." -ForegroundColor Yellow
flutter pub get

# 3. Run full automated test suite
Write-Host "[3/4] Running automated test verification..." -ForegroundColor Yellow
flutter test
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Tests failed! Aborting release build." -ForegroundColor Red
    exit 1
}

# 4. Compile native Windows release executable
Write-Host "[4/4] Compiling native Windows C++ Release binary..." -ForegroundColor Yellow
flutter build windows --release

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "BUILD SUCCESSFUL!" -ForegroundColor Green
    Write-Host "Release output directory: build\windows\x64\runner\Release" -ForegroundColor Green
    Write-Host "Ready for Inno Setup compiler: iscc installer\alfa_soft_setup.iss" -ForegroundColor Cyan
} else {
    Write-Host "BUILD FAILED!" -ForegroundColor Red
    exit 1
}
