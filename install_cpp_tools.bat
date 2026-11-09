@echo off
chcp 65001 >nul
echo =================================================================
echo  ALFA SOFT - مثبت أدوات C++ المخفف (الحد الأدنى ~1 جيجا فقط)
echo =================================================================
echo.
echo جاري تحميل وتثبيت المكونات الأساسية الثلاثة فقط (بدون أي ملحقات إضافية)...
echo 1. MSVC C++ Build Tools
echo 2. C++ CMake Tools
echo 3. Windows 10 SDK Core
echo.
echo يرجى الانتظار بينما يتم التحميل والتثبيت التلقائي...
echo.

"C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe" modify --installPath "C:\Program Files\Microsoft Visual Studio\2022\Community" --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.VC.CMake.Project --add Microsoft.VisualStudio.Component.Windows10SDK.19041 --passive --norestart

if %ERRORLEVEL% EQU 0 (
    echo.
    echo =============================================================
    echo  تم تثبيت المكونات بنجاح! جاري بناء برنامج الفا سوفت الآن...
    echo =============================================================
    echo.
    cd /d "e:\الفا سوفت"
    call ".\scripts\build_windows_release.bat"
) else (
    echo.
    echo تنبيه: إذا ظهرت هذه الرسالة، يرجى النقر بزر الفأرة الأيمن على الملف واختيار:
    echo "تشغيل كمسؤول (Run as administrator)"
)

pause
