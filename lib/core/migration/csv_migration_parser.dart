import 'dart:convert';

class ParsedCsvData {
  final List<String> headers;
  final List<List<String>> rows;
  final String delimiter;

  const ParsedCsvData({
    required this.headers,
    required this.rows,
    required this.delimiter,
  });

  int get rowCount => rows.length;
}

/// Robust CSV/TSV text parser with automatic delimiter detection and UTF-8 handling
class CsvMigrationParser {
  const CsvMigrationParser._();

  static ParsedCsvData parse(String rawContent) {
    if (rawContent.trim().isEmpty) {
      return const ParsedCsvData(headers: [], rows: [], delimiter: ',');
    }

    // Strip BOM if present
    String content = rawContent;
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }

    final lines = const LineSplitter().convert(content)
        .where((l) => l.trim().isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return const ParsedCsvData(headers: [], rows: [], delimiter: ',');
    }

    // Auto-detect delimiter from the first line
    final firstLine = lines.first;
    final delimiter = _detectDelimiter(firstLine);

    final rawHeaders = _splitLine(firstLine, delimiter);
    final headers = rawHeaders.map((h) => h.trim().replaceAll('"', '')).toList();

    final rows = <List<String>>[];
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i];
      final cols = _splitLine(line, delimiter).map((c) => c.trim().replaceAll('"', '')).toList();

      // Pad or trim columns to match header count
      if (cols.length < headers.length) {
        final padded = List<String>.from(cols);
        while (padded.length < headers.length) {
          padded.add('');
        }
        rows.add(padded);
      } else {
        rows.add(cols.sublist(0, headers.length));
      }
    }

    return ParsedCsvData(
      headers: headers,
      rows: rows,
      delimiter: delimiter,
    );
  }

  static String _detectDelimiter(String line) {
    final commaCount = ','.allMatches(line).length;
    final semicolonCount = ';'.allMatches(line).length;
    final tabCount = '\t'.allMatches(line).length;

    if (semicolonCount > commaCount && semicolonCount > tabCount) return ';';
    if (tabCount > commaCount && tabCount > semicolonCount) return '\t';
    return ',';
  }

  static List<String> _splitLine(String line, String delimiter) {
    final List<String> tokens = [];
    final StringBuffer currentToken = StringBuffer();
    bool insideQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        insideQuotes = !insideQuotes;
      } else if (char == delimiter && !insideQuotes) {
        tokens.add(currentToken.toString());
        currentToken.clear();
      } else {
        currentToken.write(char);
      }
    }
    tokens.add(currentToken.toString());

    return tokens;
  }
}
