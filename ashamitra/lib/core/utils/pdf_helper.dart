import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ByteData;
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import '../theme/app_colors.dart';

/// PDF utilities. Two roles:
///
///   1. `bengaliTheme()` — returns a `pw.ThemeData` whose base + bold fonts are
///      Hind Siliguri (Bengali-capable). Apply it via `pw.Document(theme:...)`
///      or per-page so Bengali text renders as proper glyphs instead of
///      replacement boxes. First call downloads the TTF from GitHub raw and
///      caches it; subsequent calls return immediately from memory + disk.
///
///   2. `saveAndOpen()` — writes a built `pw.Document` to the device's
///      Downloads folder and opens it with the system PDF viewer.
class PdfHelper {
  // ── Font cache (memory + disk) ─────────────────────────────────────────────
  // Source: Google Fonts public mirror on GitHub. Stable, license-compliant
  // (Hind Siliguri is OFL — bundle, redistribute, ship.).
  static const _regularUrl =
      'https://raw.githubusercontent.com/google/fonts/main/ofl/hindsiliguri/HindSiliguri-Regular.ttf';
  static const _boldUrl =
      'https://raw.githubusercontent.com/google/fonts/main/ofl/hindsiliguri/HindSiliguri-Bold.ttf';

  static pw.ThemeData? _cachedTheme;
  static pw.Font? _cachedRegular;
  static pw.Font? _cachedBold;

  /// Returns a Bengali-capable PDF theme. Caches after first call.
  /// Apply via `pw.Page(theme: theme, ...)` or `pw.Document(theme: theme)`.
  static Future<pw.ThemeData> bengaliTheme() async {
    if (_cachedTheme != null) return _cachedTheme!;
    final regular = await _loadFont(bold: false);
    final bold = await _loadFont(bold: true);
    _cachedRegular = regular;
    _cachedBold = bold;
    _cachedTheme = pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: regular,
      boldItalic: bold,
    );
    return _cachedTheme!;
  }

  /// Returns a single Bengali-capable font. Useful when building styles
  /// manually with `pw.TextStyle(font: ...)`.
  static Future<pw.Font> bengaliFont({bool bold = false}) async {
    if (bold) return _cachedBold ??= await _loadFont(bold: true);
    return _cachedRegular ??= await _loadFont(bold: false);
  }

  // ── Internal: load TTF (cache → disk → network) ────────────────────────────
  static Future<pw.Font> _loadFont({required bool bold}) async {
    final fileName = bold ? 'HindSiliguri-Bold.ttf' : 'HindSiliguri-Regular.ttf';
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$fileName');

    // 1. Disk cache (works fully offline after first download)
    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      return pw.Font.ttf(ByteData.sublistView(bytes));
    }

    // 2. Network fetch (first PDF generation only — needs internet once)
    final url = bold ? _boldUrl : _regularUrl;
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
      throw Exception('Could not fetch Bengali PDF font ($url) — '
          'will fall back to a Latin-only font and Bengali will render as boxes. '
          'Try again with internet.');
    }
    await file.writeAsBytes(res.bodyBytes, flush: true);
    return pw.Font.ttf(ByteData.sublistView(res.bodyBytes));
  }

  // ── Save + open ────────────────────────────────────────────────────────────
  static Future<void> saveAndOpen(pw.Document doc, String fileName) async {
    try {
      final bytes = await doc.save();

      // Save to Downloads on Android, Documents on others
      final Directory dir;
      if (Platform.isAndroid) {
        final downloads = Directory('/storage/emulated/0/Download');
        dir = downloads.existsSync()
            ? downloads
            : await getExternalStorageDirectory() ??
                await getApplicationDocumentsDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final path = '${dir.path}/$fileName';
      await File(path).writeAsBytes(bytes, flush: true);

      final result = await OpenFile.open(path);

      if (result.type == ResultType.done) {
        Get.snackbar(
          'PDF Downloaded',
          'Saved to Downloads: $fileName',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: AppColors.safeGreen,
          colorText: Colors.white,
          margin: const EdgeInsets.all(16),
          borderRadius: 12,
          duration: const Duration(seconds: 3),
        );
      } else {
        Get.snackbar(
          'PDF Saved',
          'File saved to Downloads/$fileName\n(${result.message})',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: AppColors.safeGreen,
          colorText: Colors.white,
          margin: const EdgeInsets.all(16),
          borderRadius: 12,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        'Could not save PDF: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.emergencyRed,
        colorText: Colors.white,
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
      );
    }
  }
}
