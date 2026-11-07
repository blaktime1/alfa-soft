import 'dart:convert';
import 'dart:typed_data';

/// ZATCA (FATOORA) E-Invoicing QR Code Generator (TLV Format)
class ZatcaQrCodec {
  const ZatcaQrCodec._();

  /// Generates the Base64-encoded TLV payload required by ZATCA
  static String generateBase64Tlv({
    required String sellerName,
    required String vatRegistrationNumber,
    required DateTime timestamp,
    required double invoiceTotal,
    required double vatTotal,
  }) {
    final bytesBuilder = BytesBuilder();

    // Tag 1: Seller's Name
    _appendTlv(bytesBuilder, 1, sellerName);

    // Tag 2: VAT Registration Number (15 digits)
    _appendTlv(bytesBuilder, 2, vatRegistrationNumber);

    // Tag 3: Timestamp (ISO 8601)
    _appendTlv(bytesBuilder, 3, timestamp.toUtc().toIso8601String());

    // Tag 4: Invoice Total (with VAT) formatted to 2 decimals
    _appendTlv(bytesBuilder, 4, invoiceTotal.toStringAsFixed(2));

    // Tag 5: VAT Total formatted to 2 decimals
    _appendTlv(bytesBuilder, 5, vatTotal.toStringAsFixed(2));

    return base64Encode(bytesBuilder.toBytes());
  }

  static void _appendTlv(BytesBuilder builder, int tag, String value) {
    final valueBytes = utf8.encode(value);
    builder.addByte(tag);
    builder.addByte(valueBytes.length);
    builder.add(valueBytes);
  }

  /// Decodes a Base64-encoded TLV string into a map of tags and values
  static Map<int, String> decodeBase64Tlv(String base64Tlv) {
    final bytes = base64Decode(base64Tlv);
    final result = <int, String>{};
    int i = 0;

    while (i < bytes.length) {
      if (i + 2 > bytes.length) break;
      final tag = bytes[i];
      final length = bytes[i + 1];
      i += 2;

      if (i + length > bytes.length) break;
      final valueBytes = bytes.sublist(i, i + length);
      result[tag] = utf8.decode(valueBytes);
      i += length;
    }

    return result;
  }
}
