import 'dart:io';
import 'package:alfa_soft/core/licensing/license_service.dart';

void main(List<String> args) async {
  print('===========================================================');
  print('    ALFA SOFT — Enterprise License Generator (Ed25519)     ');
  print('===========================================================');

  final service = LicenseService();

  String? licenseeName;
  String? hwid;
  String? taxNo;
  String planType = 'LIFETIME';
  LicenseTier tier = LicenseTier.enterprise;
  int? days;
  String? notes;
  String? outputPath;

  // Parse args if provided
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--hwid' && i + 1 < args.length) hwid = args[++i];
    if (args[i] == '--name' && i + 1 < args.length) licenseeName = args[++i];
    if (args[i] == '--tax' && i + 1 < args.length) taxNo = args[++i];
    if (args[i] == '--tier' && i + 1 < args.length) tier = LicenseTier.fromString(args[++i]);
    if (args[i] == '--plan' && i + 1 < args.length) planType = args[++i];
    if (args[i] == '--days' && i + 1 < args.length) days = int.tryParse(args[++i]);
    if (args[i] == '--notes' && i + 1 < args.length) notes = args[++i];
    if (args[i] == '--out' && i + 1 < args.length) outputPath = args[++i];
  }

  // Interactive prompts if running with no command-line flags
  if (args.isEmpty) {
    if (hwid == null || hwid.isEmpty) {
      stdout.write('أدخل كود بصمة الجهاز (Hardware ID) [مثال: ALFA-XXXX-XXXX-XXXX-XXXX]: ');
      hwid = stdin.readLineSync()?.trim();
    }

    if (licenseeName == null || licenseeName.isEmpty) {
      stdout.write('أدخل اسم العميل / المنشأة: ');
      licenseeName = stdin.readLineSync()?.trim();
    }

    if (taxNo == null || taxNo.isEmpty) {
      stdout.write('أدخل الرقم الضريبي / السجل التجاري (اختياري): ');
      taxNo = stdin.readLineSync()?.trim();
    }

    stdout.write('نوع الترخيص (1: دائم مدى الحياة | 2: سنوي (365 يوم) | 3: شهري (30 يوم) | 4: عدد أيام مخصص) [الافتراضي: 1]: ');
    final choice = stdin.readLineSync()?.trim();
    if (choice == '2') {
      planType = 'ANNUAL';
      days = 365;
    } else if (choice == '3') {
      planType = 'MONTHLY';
      days = 30;
    } else if (choice == '4') {
      planType = 'CUSTOM';
      stdout.write('أدخل عدد الأيام المصرح بها: ');
      days = int.tryParse(stdin.readLineSync()?.trim() ?? '30') ?? 30;
    } else {
      planType = 'LIFETIME';
      days = null;
    }
  }

  hwid ??= 'ALFA-C075-59AF-1947-4167';
  licenseeName ??= 'عميل الفا سوفت المعتمد';
  taxNo ??= '300000000000003';

  DateTime? expiresAt;
  if (days != null && days > 0) {
    expiresAt = DateTime.now().add(Duration(days: days));
  }

  print('\nجاري توليد الترخيص والتوقيع الإلكتروني بمفتاح Ed25519 الرئيسي...');

  final licenseToken = await service.issueLicense(
    licenseeName: licenseeName,
    hardwareId: hwid,
    taxNumber: taxNo,
    tier: tier,
    planType: planType,
    expiresAt: expiresAt,
    notes: notes,
  );

  print('\n-----------------------------------------------------------');
  print('✅ تم توليد وتوقيع الترخيص بنجاح:');
  print('-----------------------------------------------------------');
  print('المنشأة:      $licenseeName');
  print('بصمة الجهاز:   $hwid');
  print('نوع الخطة:     $planType (${expiresAt == null ? "دائم مدى الحياة" : "ينتهي في: ${expiresAt.toIso8601String().substring(0, 10)} ($days يوم)"})');
  print('النسخة:        ${tier.labelAr}');
  print('-----------------------------------------------------------');
  print('مفتاح التنشيط (انسخ الكود بالكامل للعميل):');
  print(licenseToken);
  print('-----------------------------------------------------------');

  // Write .alfalic file
  final safeName = licenseeName.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');
  final fileTarget = outputPath ?? 'alfa_license_${safeName}_${hwid.substring(hwid.length - 4)}.alfalic';
  final file = File(fileTarget);
  file.writeAsStringSync(licenseToken);
  print('📁 تم حفظ ملف الترخيص الموقّع أيضاً في: ${file.absolute.path}');
  print('يمكنك إرسال الكود النصي أو ملف الترخيص للعميل عبر واتساب مباشرة.\n');
}
