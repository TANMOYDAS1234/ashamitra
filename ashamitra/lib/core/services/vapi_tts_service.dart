import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../constants/api_constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VapiTtsService
// Calls backend /api/tts → Google Cloud Chirp3-HD Leda (Bengali)
// Caches every MP3 on device so it plays offline after first use.
// Supports prefetch() for warming the cache at startup.
// ─────────────────────────────────────────────────────────────────────────────

class VapiTtsService {
  static final VapiTtsService _instance = VapiTtsService._();
  factory VapiTtsService() => _instance;
  VapiTtsService._() {
    // Wire onPlayerComplete EXACTLY ONCE — previous code added a listener
    // per speak() call, leaking N subscriptions over a session of N turns.
    _player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      onComplete?.call();
    });
    _player.onPlayerStateChanged.listen((state) {
      // Mirror Android's actual playback state so STT-restart gates can
      // see whether audio is still coming out of the speaker. Critical for
      // preventing mic bleed-back where the AI's own voice gets captured
      // by STT as if the worker said it.
      _isPlaying = state == PlayerState.playing;
    });
  }

  final _player = AudioPlayer();

  /// True while the AudioPlayer is actively rendering audio. Callers that
  /// open the mic right after a TTS turn (STT auto-restart) should wait
  /// for this to be false plus a small settle window before listening —
  /// otherwise the speaker output is captured back into STT as the next
  /// "worker input", which feeds the LLM the AI's own previous sentence.
  bool get isPlaying => _isPlaying;
  bool _isPlaying = false;
  static const _cacheLimit = 60 * 1024 * 1024; // 60 MB max cache
  // Cache-key tag only — actual voice is chosen server-side.
  // Bump this string when switching voices so old cached MP3s are not replayed.
  // History: Charon (male) → Kore (Bangladeshi-leaning) → Aoede (more Indian).
  // Bumping this tag invalidates every device's cached MP3s — the next
  // prewarm cycle will re-fetch all phrases with the new voice. Without
  // this bump, old audio would keep playing from cache.
  static const _voice = 'gcloud:Chirp3-HD-Aoede:v1';

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

  // ── Cache key: MD5 of text + voice + tone ────────────────────────────────
  String _cacheKey(String text, String tone) {
    final input = '$text|$_voice|$tone';
    return md5.convert(utf8.encode(input)).toString();
  }

  // ── Lookup priority for cached MP3:
  //   1. On-disk cache (most-used path — fastest after first hit)
  //   2. APK-bundled assets (works even on day-1 zero-internet install)
  //   3. Backend /api/tts → cache to disk
  // ──────────────────────────────────────────────────────────────────────────

  /// Returns the bundle-asset bytes for [key] if such an MP3 ships in the
  /// APK at assets/voices/<key>.mp3. Null otherwise. The generate-bundled-
  /// voices.js script produces these files using the SAME cache key, so a
  /// match here means the bundled audio is byte-identical to what the live
  /// /api/tts would produce.
  Future<List<int>?> _loadBundledAsset(String key) async {
    try {
      final data = await rootBundle.load('assets/voices/$key.mp3');
      return data.buffer.asUint8List();
    } catch (_) {
      return null; // not bundled — that's fine, fall through to network
    }
  }

  // ── Speak: disk cache → bundled asset → network ──────────────────────────
  Future<bool> speak(String text, {String tone = 'normal'}) async {
    if (text.trim().isEmpty) return false;

    final key  = _cacheKey(text, tone);
    final dir  = await _cacheDir;
    final file = File('${dir.path}/$key.mp3');

    try {
      if (!file.existsSync()) {
        // Try APK-bundled asset first (works offline-first-ever).
        final bundled = await _loadBundledAsset(key);
        if (bundled != null) {
          await file.writeAsBytes(bundled);
        } else {
          // Fall through to backend.
          final response = await http.post(
            Uri.parse('${ApiConstants.baseUrl}/tts'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text, 'tone': tone}),
          ).timeout(const Duration(seconds: 15));
          if (response.statusCode != 200) return false;
          await file.writeAsBytes(response.bodyBytes);
          await _evictIfNeeded(dir);
        }
      }

      // Play the cached MP3. Completion listener wired once in the
      // constructor; calling .listen here again would leak a subscription
      // per speak() call (see constructor comment).
      onStart?.call();
      await _player.play(DeviceFileSource(file.path));
      return true;
    } catch (_) {
      onError?.call();
      return false;
    }
  }

  /// Play [audioBytes] for [text]+[tone] without hitting the network.
  /// Used by the combined /chat-with-voice path (2b) where the server
  /// already returned the MP3 in the same response. The bytes are also
  /// written to the on-device cache under the same key as [speak] so
  /// the next time the same phrase is needed it's a pure cache hit.
  /// Returns true if playback started, false on any failure.
  Future<bool> speakBytes(
    List<int> audioBytes, {
    required String text,
    String tone = 'normal',
  }) async {
    if (audioBytes.isEmpty) return false;
    final key  = _cacheKey(text, tone);
    final dir  = await _cacheDir;
    final file = File('${dir.path}/$key.mp3');
    try {
      if (!file.existsSync()) {
        await file.writeAsBytes(audioBytes);
        await _evictIfNeeded(dir);
      }
      onStart?.call();
      // Completion listener wired once in the constructor — see speak().
      await _player.play(DeviceFileSource(file.path));
      return true;
    } catch (_) {
      onError?.call();
      return false;
    }
  }

  Future<void> stop() async => _player.stop();

  /// Returns true if [text]+[tone] is already in the local MP3 cache.
  Future<bool> isCached(String text, {String tone = 'normal'}) async {
    if (text.trim().isEmpty) return false;
    final dir  = await _cacheDir;
    final file = File('${dir.path}/${_cacheKey(text, tone)}.mp3');
    return file.existsSync();
  }

  /// Fetch and cache [text]+[tone] without playing.
  /// Used by [TtsPrewarmService] at startup to make the app offline-ready.
  /// Returns true on success (cached or just fetched), false on failure.
  /// Short timeout — prewarm is best-effort and must not block startup.
  Future<bool> prefetch(String text, {String tone = 'normal'}) async {
    if (text.trim().isEmpty) return false;
    final key  = _cacheKey(text, tone);
    final dir  = await _cacheDir;
    final file = File('${dir.path}/$key.mp3');
    if (file.existsSync()) return true;

    // Skip network if the phrase ships in the APK — copy from bundle.
    final bundled = await _loadBundledAsset(key);
    if (bundled != null) {
      await file.writeAsBytes(bundled);
      return true;
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/tts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text, 'tone': tone}),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return false;
      await file.writeAsBytes(response.bodyBytes);
      await _evictIfNeeded(dir);
      return true;
    } catch (_) {
      return false;
    }
  }

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
