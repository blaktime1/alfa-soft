import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  test('PDF generates Arabic text with TTF font without unicode error', () async {
    final fontFile = File('assets/fonts/arabic_regular.ttf');
    expect(fontFile.existsSync(), isTrue);
    final fontBytes = fontFile.readAsBytesSync();
    final ttfFont = pw.Font.ttf(fontBytes.buffer.asByteData());

    final fontBoldFile = File('assets/fonts/arabic_bold.ttf');
    expect(fontBoldFile.existsSync(), isTrue);
    final fontBoldBytes = fontBoldFile.readAsBytesSync();
    final ttfBold = pw.Font.ttf(fontBoldBytes.buffer.asByteData());

    final theme = pw.ThemeData.withFont(
      base: ttfFont,
      bold: ttfBold,
      fontFallback: [ttfFont, ttfBold],
    );

    final pdf = pw.Document(theme: theme);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              children: [
                pw.Text('شركة الفا سوفت المحدودة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                pw.Text('فاتورة ضريبية مبسطة'),
                pw.Text('الصنف: شاي كرك هيل فاخر - 1.50 ر.س'),
                pw.Text('الكمية: 1 • الإجمالي: 1.72 ر.س'),
                pw.Text('شكراً لزيارتكم • البضاعة المباعة لا ترد ولا تستبدل'),
              ],
            ),
          );
        },
      ),
    );

    final bytes = await pdf.save();
    expect(bytes.isNotEmpty, isTrue);
    expect(bytes.sublist(0, 5), equals([0x25, 0x50, 0x44, 0x46, 0x2D])); // %PDF-
  });
}
