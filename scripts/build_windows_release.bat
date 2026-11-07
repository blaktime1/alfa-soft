@echo off
echo =================================================================
echo  ALFA SOFT - Windows Desktop Native Release Compiler
echo =================================================================

echo [1/4] Cleaning previous build artifacts...
call flutter clean
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: flutter clean failed!
    exit /b %ERRORLEVEL%
)

echo [2/4] Resolving dependencies...
call flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: flutter pub get failed!
    exit /b %ERRORLEVEL%
)

echo [3/4] Running automated test verification...
call flutter test
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: flutter test failed! Aborting release build.
    exit /b %ERRORLEVEL%
)

echo [4/4] Compiling native Windows C++ Release binary...
call flutter build windows --release
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: flutter build windows failed!
    exit /b %ERRORLEVEL%
)

echo.
echo BUILD SUCCESSFUL!
echo Release output directory: build\windows\x64\runner\Release
echo Ready for Inno Setup compiler: iscc installer\alfa_soft_setup.iss
