import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ByteData, rootBundle;
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

  // ── Internal: load TTF — bundled asset → disk cache → network ──────────────
  // Order changed: bundled asset comes FIRST so a fresh install with no
  // internet still produces Bengali PDFs without crashing. The disk cache
  // and network fallback remain for older builds that didn't ship the
  // bundled fonts (legacy compatibility).
  static Future<pw.Font> _loadFont({required bool bold}) async {
    final fileName = bold ? 'HindSiliguri-Bold.ttf' : 'HindSiliguri-Regular.ttf';

    // 1. Bundled asset (always present in this build — zero-internet safe).
    try {
      final data = await rootBundle.load('assets/fonts/$fileName');
      return pw.Font.ttf(data);
    } catch (_) {
      // Asset missing or unreadable — fall through to disk/network.
    }

    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$fileName');

    // 2. Disk cache (from a prior network fetch by an older build).
    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      return pw.Font.ttf(ByteData.sublistView(bytes));
    }

    // 3. Network fetch (last resort).
    try {
      final url = bold ? _boldUrl : _regularUrl;
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(res.bodyBytes, flush: true);
        return pw.Font.ttf(ByteData.sublistView(res.bodyBytes));
      }
    } catch (_) {
      // Fall through to Helvetica fallback.
    }

    // 4. Final fallback — Helvetica. Bengali glyphs will render as boxes,
    // but the PDF will at least generate without crashing the app. The
    // caller (reports_screen) can show a "limited PDF" snackbar if the
    // font load failed, but never an unhandled exception.
    return pw.Font.helvetica();
  }

  // ── Save + open ────────────────────────────────────────────────────────────
  /// Writes the [doc] to a folder the app is allowed to write to without
  /// requesting scary system permissions, then opens it in the system PDF
  /// viewer. From the viewer the worker can read, print, share via
  /// WhatsApp / Drive / email — anywhere they want.
  ///
  /// Why not /storage/emulated/0/Download directly?
  ///   That requires MANAGE_EXTERNAL_STORAGE on Android 11+ (SDK 30+), which
  ///   is a dangerous-permission special-settings flow. The previous code
  ///   tried writeAsBytes to /Download, got permission-denied silently, and
  ///   the user saw "PDF Downloaded" but no file actually appeared.
  ///
  /// What does work:
  ///   getExternalStorageDirectory() returns the app's private external
  ///   folder (e.g. /storage/emulated/0/Android/data/com.example.asha_mitra/
  ///   files/). The app can read/write here on all Android versions without
  ///   any permissions. The file IS visible in Files apps under the app's
  ///   data folder, and OpenFile.open() launches the system PDF viewer
  ///   regardless.
  static Future<void> saveAndOpen(pw.Document doc, String fileName) async {
    try {
      final bytes = await doc.save();

      // Resolve a writable directory we don't need permissions for.
      final Directory dir;
      if (Platform.isAndroid) {
        // App-scoped external storage. Use a subfolder so multiple PDFs
        // don't clutter the root.
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

      // ResultType.done = viewer launched OK; otherwise we still saved the
      // file but the platform couldn't find a viewer (rare — every Android
      // device has at least the Files app or Drive).
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
        'Could not generate PDF: $e',
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
