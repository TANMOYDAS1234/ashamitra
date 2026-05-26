import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import '../theme/app_colors.dart';

class PdfHelper {
  static const _regularUrl =
      'https://raw.githubusercontent.com/google/fonts/main/ofl/hindsiliguri/HindSiliguri-Regular.ttf';
  static const _boldUrl =
      'https://raw.githubusercontent.com/google/fonts/main/ofl/hindsiliguri/HindSiliguri-Bold.ttf';

  static Uint8List? _cachedRegularBytes;
  static Uint8List? _cachedBoldBytes;

  // Returns raw font bytes — safe to send across isolate boundaries.
  static Future<Uint8List> loadFontBytes({required bool bold}) async {
    if (bold && _cachedBoldBytes != null) return _cachedBoldBytes!;
    if (!bold && _cachedRegularBytes != null) return _cachedRegularBytes!;

    final fileName =
        bold ? 'HindSiliguri-Bold.ttf' : 'HindSiliguri-Regular.ttf';

    // 1. Bundled asset.
    try {
      final data = await rootBundle.load('assets/fonts/$fileName');
      final bytes = Uint8List.sublistView(data);
      if (bold) {
        _cachedBoldBytes = bytes;
      } else {
        _cachedRegularBytes = bytes;
      }
      return bytes;
    } catch (_) {}

    // 2. Disk cache.
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$fileName');
    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      if (bold) {
        _cachedBoldBytes = bytes;
      } else {
        _cachedRegularBytes = bytes;
      }
      return bytes;
    }

    // 3. Network.
    try {
      final url = bold ? _boldUrl : _regularUrl;
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(res.bodyBytes, flush: true);
        if (bold) {
          _cachedBoldBytes = res.bodyBytes;
        } else {
          _cachedRegularBytes = res.bodyBytes;
        }
        return res.bodyBytes;
      }
    } catch (_) {}

    // 4. Empty bytes — pw.Font.helvetica() will be used by the isolate.
    return Uint8List(0);
  }

  // Kept for any callers that still use the theme directly on the UI thread.
  static Future<pw.ThemeData> bengaliTheme() async {
    final regular = await loadFontBytes(bold: false);
    final bold = await loadFontBytes(bold: true);
    pw.Font makeFont(Uint8List b) =>
        b.isNotEmpty ? pw.Font.ttf(b.buffer.asByteData()) : pw.Font.helvetica();
    return pw.ThemeData.withFont(
      base: makeFont(regular),
      bold: makeFont(bold),
      italic: makeFont(regular),
      boldItalic: makeFont(bold),
    );
  }

  /// Writes [pdfBytes] to app-scoped storage and opens the system PDF viewer.
  static Future<void> saveAndOpen(
      List<int> pdfBytes, String fileName) async {
    try {
      final Directory dir;
      if (Platform.isAndroid) {
        final external = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
        dir = Directory('${external.path}/asha_reports');
        if (!dir.existsSync()) dir.createSync(recursive: true);
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final path = '${dir.path}/$fileName';
      await File(path).writeAsBytes(pdfBytes, flush: true);

      final result = await OpenFile.open(path);
      final sizeKb = (pdfBytes.length / 1024).toStringAsFixed(1);

      Get.snackbar(
        result.type == ResultType.done ? 'PDF Opened' : 'PDF Saved',
        result.type == ResultType.done
            ? 'Share via the viewer. File: $fileName ($sizeKb KB)'
            : 'Saved as $fileName ($sizeKb KB). ${result.message}',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.safeGreen,
        colorText: Colors.white,
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
        duration: const Duration(seconds: 5),
      );
    } catch (e) {
      Get.snackbar(
        'PDF failed',
        'Could not save PDF: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.emergencyRed,
        colorText: Colors.white,
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
        duration: const Duration(seconds: 6),
      );
    }
  }

  /// Same as [saveAndOpen] but takes pre-computed PDF bytes — used when the
  /// document was built and serialized in a background isolate (e.g. from
  /// [_buildPdfBytes] in reports_screen.dart). Skips the doc.save() call
  /// since the bytes are already in hand.
  static Future<void> saveBytesAndOpen(List<int> bytes, String fileName) async {
    try {
      final Directory dir;
      if (Platform.isAndroid) {
        final external = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
        dir = Directory('${external.path}/asha_reports');
        if (!dir.existsSync()) dir.createSync(recursive: true);
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final path = '${dir.path}/$fileName';
      await File(path).writeAsBytes(bytes, flush: true);

      final result = await OpenFile.open(path);
      final saved = File(path);
      final sizeKb = saved.existsSync()
          ? (saved.lengthSync() / 1024).toStringAsFixed(1)
          : '?';
      Get.snackbar(
        result.type == ResultType.done ? 'PDF Opened' : 'PDF Saved',
        result.type == ResultType.done
            ? 'Use the share button in the viewer to send via WhatsApp, '
                'Drive, print, etc. File: $fileName ($sizeKb KB)'
            : 'Saved as $fileName ($sizeKb KB). ${result.message}. '
                'Open Files → Internal Storage → Android/data → '
                'com.example.asha_mitra → files → asha_reports.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.safeGreen,
        colorText: Colors.white,
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
        duration: const Duration(seconds: 5),
      );
    } catch (e) {
      Get.snackbar(
        'PDF failed',
        'Could not save PDF: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.emergencyRed,
        colorText: Colors.white,
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
        duration: const Duration(seconds: 6),
      );
    }
  }
}
