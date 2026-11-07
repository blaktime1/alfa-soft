import 'dart:convert';
import 'dart:typed_data';

enum EscPosPaperSize {
  mm80(48),
  mm58(32);

  final int maxColumns;
  const EscPosPaperSize(this.maxColumns);
}

enum EscPosAlign {
  left(0),
  center(1),
  right(2);

  final int value;
  const EscPosAlign(this.value);
}

/// Raw Byte ESC/POS Thermal Receipt Generator
class EscPosBuilder {
  final EscPosPaperSize paperSize;
  final BytesBuilder _builder = BytesBuilder();

  EscPosBuilder({this.paperSize = EscPosPaperSize.mm80}) {
    initialize();
  }

  void initialize() {
    _builder.add([0x1B, 0x40]); // ESC @
  }

  void setAlign(EscPosAlign align) {
    _builder.add([0x1B, 0x61, align.value]); // ESC a n
  }

  void setBold(bool enable) {
    _builder.add([0x1B, 0x45, enable ? 0x01 : 0x00]); // ESC E n
  }

  void setDoubleSize(bool enable) {
    _builder.add([0x1D, 0x21, enable ? 0x11 : 0x00]); // GS ! n
  }

  void lineFeed([int lines = 1]) {
    for (int i = 0; i < lines; i++) {
      _builder.addByte(0x0A); // LF
    }
  }

  void text(String text, {
    EscPosAlign align = EscPosAlign.left,
    bool bold = false,
    bool doubleSize = false,
  }) {
    setAlign(align);
    if (bold) setBold(true);
    if (doubleSize) setDoubleSize(true);

    _builder.add(utf8.encode(text));
    _builder.addByte(0x0A); // LF

    if (bold) setBold(false);
    if (doubleSize) setDoubleSize(false);
  }

  void divider({String char = '-'}) {
    final line = char * paperSize.maxColumns;
    text(line, align: EscPosAlign.center);
  }

  void twoColumn(String left, String right, {bool bold = false}) {
    final available = paperSize.maxColumns;
    final totalLen = left.length + right.length;

    if (totalLen >= available) {
      final truncatedLeft = left.length > (available - right.length - 1)
          ? '${left.substring(0, available - right.length - 2)}.'
          : left;
      final spaces = available - (truncatedLeft.length + right.length);
      final spaceStr = ' ' * (spaces > 0 ? spaces : 1);
      text('$truncatedLeft$spaceStr$right', bold: bold);
    } else {
      final spaces = ' ' * (available - totalLen);
      text('$left$spaces$right', bold: bold);
    }
  }

  void itemRow({
    required String name,
    required String qty,
    required String price,
    required String total,
  }) {
    if (paperSize == EscPosPaperSize.mm80) {
      // 80mm Layout: Name(22) | Qty(6) | Price(10) | Total(10) = 48
      final nameCol = name.length > 21 ? '${name.substring(0, 19)}..' : name.padRight(22);
      final qtyCol = qty.padLeft(6);
      final priceCol = price.padLeft(10);
      final totalCol = total.padLeft(10);
      text('$nameCol$qtyCol$priceCol$totalCol');
    } else {
      // 58mm Layout: Name(14) | Qty(4) | Price(7) | Total(7) = 32
      final nameCol = name.length > 13 ? '${name.substring(0, 11)}..' : name.padRight(14);
      final qtyCol = qty.padLeft(4);
      final priceCol = price.padLeft(7);
      final totalCol = total.padLeft(7);
      text('$nameCol$qtyCol$priceCol$totalCol');
    }
  }

  /// Appends native ESC/POS Model 2 QR Code commands
  void qrCode(String data) {
    final dataBytes = utf8.encode(data);
    final len = dataBytes.length + 3;
    final pL = len % 256;
    final pH = len ~/ 256;

    setAlign(EscPosAlign.center);

    // 1. Model type (Model 2)
    _builder.add([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);

    // 2. Module size (e.g. 5 dots)
    _builder.add([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x05]);

    // 3. Error correction level (Level M: 0x31)
    _builder.add([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31]);

    // 4. Store QR Data in symbol storage area
    _builder.add([0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30]);
    _builder.add(dataBytes);

    // 5. Print the QR symbol
    _builder.add([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
    lineFeed(1);
  }

  /// Pulse cash drawer pin 2 (kick open cash drawer)
  void openCashDrawer() {
    _builder.add([0x1B, 0x70, 0x00, 0x19, 0xFA]); // ESC p 0 25 250
  }

  /// Feed paper and execute partial cut
  void cut() {
    lineFeed(4);
    _builder.add([0x1D, 0x56, 0x42, 0x00]); // GS V 66 0
  }

  Uint8List toBytes() {
    return _builder.toBytes();
  }
}
