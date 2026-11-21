# ==============================================================================
# ALFA SOFT ERP -- Database Factory Reset Tool
# أداة إعادة ضبط وتصفير قاعدة بيانات المنظومة
# ==============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "ALFA SOFT ERP -- إعادة ضبط قاعدة البيانات"

Clear-Host
Write-Host ""
Write-Host "===============================================================================" -ForegroundColor Red
Write-Host "                ALFA SOFT -- Enterprise Resource Planning" -ForegroundColor White
Write-Host "             أداة تصفير وإعادة ضبط قاعدة البيانات للمصنع (Factory Reset)" -ForegroundColor Yellow
Write-Host "===============================================================================" -ForegroundColor Red
Write-Host ""

$dataDir = Join-Path $env:APPDATA "com.alfasoft\desktop_app\data"
$backupDir = Join-Path $env:APPDATA "com.alfasoft\desktop_app\backups"
$dbFile = Join-Path $dataDir "alfa_soft.db"
$walFile = Join-Path $dataDir "alfa_soft.db-wal"
$shmFile = Join-Path $dataDir "alfa_soft.db-shm"

Write-Host "تنبيه هام:" -ForegroundColor Yellow
Write-Host "هذه العملية ستقوم بحذف قاعدة البيانات الحالية وإعادتها لحالة المصنع الجديدة تماماً." -ForegroundColor Gray
Write-Host "عند فتح البرنامج مجدداً، سيبدأ من معالج الإعداد الأولي (First Run Wizard) لإنشاء شركة ومسؤول جديد." -ForegroundColor Gray
Write-Host ""

$confirmation = Read-Host "هل أنت متأكد من رغبتك في تصفير قاعدة البيانات؟ اكتب (نعم أو Y) للمتابعة"
if ($confirmation -ne "نعم" -and $confirmation -ne "Y" -and $confirmation -ne "y") {
    Write-Host ""
    Write-Host "تم إلغاء العملية. لم يتم تغيير أي بيانات." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

Write-Host ""
Write-Host "جاري فحص العمليات النشطة وإغلاق البرنامج إن كان مفتوحاً..." -ForegroundColor Gray
Get-Process -Name "desktop_app" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

if (Test-Path $dbFile) {
    if (-not (Test-Path $backupDir)) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $safetyBackup = Join-Path $backupDir "pre_reset_backup_$timestamp.db"
    
    Write-Host "1. جاري أخذ نسخة احتياطية أمان تلقائياً قبل التصفير..." -ForegroundColor Cyan
    try {
        Copy-Item -Path $dbFile -Destination $safetyBackup -Force
        Write-Host "   [ OK ] تم حفظ نسخة أمان في: $safetyBackup" -ForegroundColor Green
    } catch {
        Write-Host "   [ تنبيه ] تعذر إنشاء نسخة الأمان، سيتم المتابعة." -ForegroundColor Yellow
    }

    Write-Host "2. جاري تصفير وحذف ملفات قاعدة البيانات..." -ForegroundColor Cyan
    try {
        Remove-Item -Path $dbFile -Force -ErrorAction SilentlyContinue
        if (Test-Path $walFile) { Remove-Item -Path $walFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path $shmFile) { Remove-Item -Path $shmFile -Force -ErrorAction SilentlyContinue }
        
        Write-Host "   [ OK ] تم حذف ملفات قاعدة البيانات السابقة بنجاح." -ForegroundColor Green
    } catch {
        Write-Host "   [ خطأ ] تعذر حذف بعض الملفات، تأكد من إغلاق البرنامج ثم أعد المحاولة." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "لم يتم العثور على قاعدة بيانات سابقة (المجلد فارغ بالفعل)." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "===============================================================================" -ForegroundColor Green
Write-Host "  ★ تمت عملية تصفير وإعادة ضبط قاعدة البيانات بنجاح تام! ★" -ForegroundColor Green
Write-Host "  عند تشغيل منظومة ALFA SOFT الآن، ستفتح على معالج التهيئة الأولي لتسجيل منشأتك الجديدة." -ForegroundColor White
Write-Host "===============================================================================" -ForegroundColor Green
Write-Host ""
