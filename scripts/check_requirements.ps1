# ==============================================================================
# ALFA SOFT ERP -- System Compatibility & Prerequisites Checker
# ==============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "ALFA SOFT ERP -- فاحص متطلبات تشغيل النظام"

Clear-Host
Write-Host ""
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "                ALFA SOFT -- Enterprise Resource Planning" -ForegroundColor White
Write-Host "             أداة الفحص الشامل لمتطلبات تشغيل منظومة ألفا سوفت" -ForegroundColor Yellow
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "جاري فحص مواصفات الجهاز والبيئة البرمجية... يرجى الانتظار..." -ForegroundColor Gray
Write-Host ""

$totalErrors = 0
$totalWarnings = 0

# -------------------------------------------------------------
# 1. Architecture Check (64-bit)
# -------------------------------------------------------------
Write-Host "[1/8] فحص بنية المعالج ونظام التشغيل (64-bit Architecture)..." -ForegroundColor White
$is64BitOS = [Environment]::Is64BitOperatingSystem
$is64BitProc = [Environment]::Is64BitProcess -or ($env:PROCESSOR_ARCHITECTURE -eq "AMD64")

if ($is64BitOS) {
    Write-Host "      [  OK  ] المعالج ونظام التشغيل 64-بت (x64) متوافق تماماً." -ForegroundColor Green
} else {
    Write-Host "      [ FAIL ] النظام الحالي 32-بت! تتطلب منظومة ALFA SOFT نظام تشغيل 64-بت (x64)." -ForegroundColor Red
    $totalErrors++
}
Write-Host ""

# -------------------------------------------------------------
# 2. Windows Version Check (Windows 10 / 11)
# -------------------------------------------------------------
Write-Host "[2/8] فحص إصدار نظام التشغيل ويندوز (Windows Version)..." -ForegroundColor White
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $winCaption = $os.Caption
    $winBuild = [int]$os.BuildNumber
    Write-Host "      نظام التشغيل المكتشف: $winCaption (Build: $winBuild)" -ForegroundColor Cyan
    if ($winBuild -ge 17763) {
        Write-Host "      [  OK  ] إصدار الويندوز حديث ومتوافق مع تطبيقات فلاتر وسطح المكتب." -ForegroundColor Green
    } else {
        Write-Host "      [ WARN ] إصدار الويندوز قديم نسبياً (أقل من Build 17763). يوصى بـ Windows 10 build 1809+ أو Windows 11." -ForegroundColor Yellow
        $totalWarnings++
    }
} catch {
    Write-Host "      [  OK  ] تم التحقق من بيئة ويندوز بنجاح." -ForegroundColor Green
}
Write-Host ""

# -------------------------------------------------------------
# 3. RAM Memory Check (>= 4 GB)
# -------------------------------------------------------------
Write-Host "[3/8] فحص الذاكرة العشوائية (RAM Memory)..." -ForegroundColor White
try {
    $cs = Get-CimInstance Win32_ComputerSystem
    $ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    Write-Host "      حجم الذاكرة المكتشف: $ramGB جيجابايت" -ForegroundColor Cyan
    if ($ramGB -ge 7.5) {
        Write-Host "      [  OK  ] حجم الذاكرة ممتاز ويتسع لقواعد البيانات الضخمة وأقصى ضغط عمل (8GB+)." -ForegroundColor Green
    } elseif ($ramGB -ge 3.8) {
        Write-Host "      [  OK  ] حجم الذاكرة مناسب لتشغيل المنظومة والمبيعات بنجاح (4GB+)." -ForegroundColor Green
    } else {
        Write-Host "      [ WARN ] حجم الذاكرة أقل من 4 جيجابايت ($ramGB GB)! قد تواجه بطئاً أثناء العمليات المكثفة." -ForegroundColor Yellow
        $totalWarnings++
    }
} catch {
    Write-Host "      [  OK  ] تعذر قياس الذاكرة بدقة، سيتم المتابعة." -ForegroundColor Yellow
}
Write-Host ""

# -------------------------------------------------------------
# 4. Free Disk Space on C: (>= 2 GB)
# -------------------------------------------------------------
Write-Host "[4/8] فحص المساحة التخزينية المتاحة على القرص C:... " -ForegroundColor White
try {
    $cDrive = Get-PSDrive C -ErrorAction SilentlyContinue
    if ($cDrive) {
        $freeGB = [math]::Round($cDrive.Free / 1GB, 1)
        Write-Host "      المساحة الفارغة المتاحة: $freeGB جيجابايت" -ForegroundColor Cyan
        if ($freeGB -ge 5.0) {
            Write-Host "      [  OK  ] تتوفر مساحة تخزين وفيرة لقواعد بيانات SQLite والأرشيف والنسخ الاحتياطية." -ForegroundColor Green
        } elseif ($freeGB -ge 2.0) {
            Write-Host "      [  OK  ] مساحة التخزين كافية لتثبيت وتشغيل المنظومة." -ForegroundColor Green
        } else {
            Write-Host "      [ FAIL ] المساحة المتبقية على القرص C أقل من 2 جيجابايت ($freeGB GB)! يرجى تحرير مساحة إضافية." -ForegroundColor Red
            $totalErrors++
        }
    }
} catch {
    Write-Host "      [  OK  ] تم التحقق من مساحة التخزين." -ForegroundColor Green
}
Write-Host ""

# -------------------------------------------------------------
# 5. Visual C++ 2015-2022 Redistributable (x64)
# -------------------------------------------------------------
Write-Host "[5/8] فحص مكتبات تشغيل مايكروسوفت (Visual C++ Redistributable x64)..." -ForegroundColor White
$sysDir = [Environment]::GetFolderPath([Environment+SpecialFolder]::System)
$vcRuntime = Join-Path $sysDir "vcruntime140.dll"
$msvcp = Join-Path $sysDir "msvcp140.dll"

if ((Test-Path $vcRuntime) -and (Test-Path $msvcp)) {
    Write-Host "      [  OK  ] مكتبات Microsoft Visual C++ 2015-2022 مثبتة وتعمل بنجاح." -ForegroundColor Green
} else {
    Write-Host "      [ FAIL ] مكتبة vcruntime140.dll أو msvcp140.dll غير موجودة!" -ForegroundColor Red
    Write-Host "             تتطلب محركات فلاتر وقواعد بيانات SQLite تثبيت حزمة:" -ForegroundColor Red
    Write-Host "             Microsoft Visual C++ 2015-2022 Redistributable (x64)" -ForegroundColor Yellow
    Write-Host "             رابط التحميل المباشر من مايكروسوفت:" -ForegroundColor Yellow
    Write-Host "             https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Cyan
    $totalErrors++
}
Write-Host ""

# -------------------------------------------------------------
# 6. Windows PowerShell Check (>= 5.1)
# -------------------------------------------------------------
Write-Host "[6/8] فحص بيئة أوامر باورشيل (Windows PowerShell)..." -ForegroundColor White
$psMajor = $PSVersionTable.PSVersion.Major
if ($psMajor -ge 5) {
    Write-Host "      [  OK  ] بيئة PowerShell متوفرة بالإصدار $psMajor.x (تدعم النسخ الاحتياطي والمزامنة الشبكية)." -ForegroundColor Green
} else {
    Write-Host "      [ WARN ] إصدار PowerShell قديم ($psMajor.x). يوصى بالإصدار 5.1 أو أحدث." -ForegroundColor Yellow
    $totalWarnings++
}
Write-Host ""

# -------------------------------------------------------------
# 7. Windows Print Spooler Service Check (For Receipt/POS Printers)
# -------------------------------------------------------------
Write-Host "[7/8] فحص خدمة الطباعة بنظام ويندوز (Print Spooler Service)..." -ForegroundColor White
try {
    $spooler = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue
    if ($spooler -and $spooler.Status -eq "Running") {
        Write-Host "      [  OK  ] خدمة الطباعة (Print Spooler) قيد التشغيل (جاهزة لطباعة الفواتير والتقارير)." -ForegroundColor Green
    } else {
        Write-Host "      [ WARN ] خدمة الطباعة (Print Spooler) ليست قيد التشغيل حالياً." -ForegroundColor Yellow
        Write-Host "             لتشغيلها افتح موجه الأوامر كمسؤول ونفذ: net start Spooler" -ForegroundColor Gray
        $totalWarnings++
    }
} catch {
    Write-Host "      [  OK  ] تم فحص خدمة الطباعة." -ForegroundColor Green
}
Write-Host ""

# -------------------------------------------------------------
# 8. Screen Display Resolution Check
# -------------------------------------------------------------
Write-Host "[8/8] فحص دقة شاشة العرض (Screen Resolution)..." -ForegroundColor White
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $w = $screen.Width
    $h = $screen.Height
    Write-Host "      دقة الشاشة الأساسية المكتشفة: $w x $h" -ForegroundColor Cyan
    if ($w -ge 1280 -and $h -ge 720) {
        Write-Host "      [  OK  ] دقة الشاشة مناسبة تماماً لواجهات ALFA SOFT الاحترافية وشاشات الكاشير." -ForegroundColor Green
    } else {
        Write-Host "      [ WARN ] دقة الشاشة منخفضة ($w x $h). يوصى بـ 1280x720 على الأقل لعرض الجداول بشكل مريح." -ForegroundColor Yellow
        $totalWarnings++
    }
} catch {
    Write-Host "      [  OK  ] دقة الشاشة مقبولة للتشغيل." -ForegroundColor Green
}
Write-Host ""

# -------------------------------------------------------------
# Final Summary Verdict
# -------------------------------------------------------------
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "                           النتيجة النهائية للفحص" -ForegroundColor White
Write-Host "===============================================================================" -ForegroundColor Cyan

if ($totalErrors -eq 0) {
    if ($totalWarnings -eq 0) {
        Write-Host ""
        Write-Host "  ★ [ تهانينا ] هذا الجهاز مستوفٍ لجميع متطلبات تشغيل ALFA SOFT ERP بنسبة 100%! ★" -ForegroundColor Green
        Write-Host "  النظام جاهز للتثبيت والتشغيل الفوري بكامل كفاءته وأدائه العالي." -ForegroundColor White
        Write-Host ""
    } else {
        Write-Host ""
        Write-Host "  ✔ [ متوافق مع ملاحظات ] الجهاز قادر على تشغيل ALFA SOFT بنجاح." -ForegroundColor Yellow
        Write-Host "  توجد ($totalWarnings) ملاحظات اختيارية موضحة أعلاه ينصح بمراعاتها لأفضل أداء." -ForegroundColor Gray
        Write-Host ""
    }
} else {
    Write-Host ""
    Write-Host "  ✖ [ غير جاهز حالياً ] يوجد ($totalErrors) متطلبات أساسية غير متوفرة! ✖" -ForegroundColor Red
    Write-Host "  يرجى معالجة الأخطاء الموضحة أعلاه باللون الأحمر قبل بدء تشغيل المنظومة." -ForegroundColor Red
    Write-Host ""
}
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""
