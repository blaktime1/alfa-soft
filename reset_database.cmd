@echo off
setlocal
chcp 65001 >nul 2>&1
title ALFA SOFT ERP - Database Factory Reset

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\reset_database.ps1"

echo.
echo Press any key to exit...
pause >nul
