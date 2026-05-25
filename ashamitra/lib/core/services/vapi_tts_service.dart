import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../constants/api_constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VapiTtsService
// Calls backend /api/tts → ElevenLabs (multilingual, incl. Bengali)
// Caches every MP3 on device so it plays offline after first use
// ─────────────────────────────────────────────────────────────────────────────

class VapiTtsService {
  static final VapiTtsService _instance = VapiTtsService._();
  factory VapiTtsService() => _instance;
  VapiTtsService._();

  final _player = AudioPlayer();
  static const _cacheLimit = 60 * 1024 * 1024; // 60 MB max cache
  // Cache-key tag only — actual voice is chosen server-side from ELEVENLABS_VOICE_ID.
  // Bump this string when switching voices so old cached MP3s are not replayed.
  static const _voice = 'elevenlabs:default';

  Function()? onStart;
  Function()? onComplete;
  Function()? onError;

  // ── Cache directory ───────────────────────────────────────────────────────
  Future<Directory> get _cacheDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/tts_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  // ── Cache key: MD5 of text + voice ───────────────────────────────────────
  String _cacheKey(String text) {
    final input = '$text|$_voice';
    return md5.convert(utf8.encode(input)).toString();
  }

  // ── Speak: cache hit → play file, miss → fetch → cache → play ────────────
  Future<bool> speak(String text) async {
    if (text.trim().isEmpty) return false;

    final key  = _cacheKey(text);
    final dir  = await _cacheDir;
    final file = File('${dir.path}/$key.mp3');

    try {
      if (!file.existsSync()) {
        // Fetch from backend proxy
        final response = await http.post(
          Uri.parse('${ApiConstants.baseUrl}/tts'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'text': text}),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode != 200) return false;

        // Save to cache
        await file.writeAsBytes(response.bodyBytes);
        await _evictIfNeeded(dir);
      }

      // Play the cached MP3
      onStart?.call();
      _player.onPlayerComplete.listen((_) => onComplete?.call());
      await _player.play(DeviceFileSource(file.path));
      return true;
    } catch (_) {
      onError?.call();
      return false;
    }
  }

  Future<void> stop() async => _player.stop();

  // ── Evict oldest files if cache exceeds limit ─────────────────────────────
  Future<void> _evictIfNeeded(Directory dir) async {
    final files = dir.listSync().whereType<File>().toList();
    int total = files.fold(0, (sum, f) => sum + f.lengthSync());
    if (total <= _cacheLimit) return;

    // Sort oldest first
    files.sort((a, b) =>
        a.statSync().modified.compareTo(b.statSync().modified));

    for (final f in files) {
      if (total <= _cacheLimit) break;
      total -= f.lengthSync();
      f.deleteSync();
    }
  }

  // ── Cache stats (for debugging) ───────────────────────────────────────────
  Future<({int files, int bytes})> cacheStats() async {
    final dir = await _cacheDir;
    final files = dir.listSync().whereType<File>().toList();
    final bytes = files.fold(0, (sum, f) => sum + f.lengthSync());
    return (files: files.length, bytes: bytes);
  }

  Future<void> clearCache() async {
    final dir = await _cacheDir;
    dir.deleteSync(recursive: true);
  }
}
