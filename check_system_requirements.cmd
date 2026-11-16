@echo off
setlocal
chcp 65001 >nul 2>&1
title ALFA SOFT ERP - System Compatibility Checker

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\check_requirements.ps1"

echo.
echo Press any key to exit...
pause >nul
