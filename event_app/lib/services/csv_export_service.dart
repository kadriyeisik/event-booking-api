import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class CsvExportService {
  static Future<void> shareCsv({
    required String filenamePrefix,
    required List<String> headers,
    required List<List<String>> rows,
    String? shareText,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln(headers.map(_escape).join(','));

    for (final row in rows) {
      buffer.writeln(row.map(_escape).join(','));
    }

    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${directory.path}/$filenamePrefix-$timestamp.csv');
    await file.writeAsString(buffer.toString());

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: shareText),
    );
  }

  static String _escape(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }
}
