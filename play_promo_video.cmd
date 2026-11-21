@echo off
setlocal
chcp 65001 >nul 2>&1
title ALFA SOFT ERP - تشغيل الفيديو الإعلاني

echo تشغيل الفيديو الإعلاني الترويجي لمنظومة ALFA SOFT...
start "" "%~dp0promo_video\alfa_soft_promo.mp4"
exit /b 0
