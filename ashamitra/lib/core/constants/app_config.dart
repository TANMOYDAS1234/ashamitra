// ─────────────────────────────────────────────────────────────────────────────
// AppConfig — Change 4: Secure API key management
//
// Keys are injected at build time via --dart-define, never hardcoded in source.
//
// Build command:
//   flutter run --dart-define=GEMINI_API_KEY=your_key_here
//   flutter build apk --dart-define=GEMINI_API_KEY=your_key_here
//
// For CI/CD: set GEMINI_API_KEY as a secret environment variable and pass it
// via --dart-define=$(GEMINI_API_KEY) in your build script.
// ─────────────────────────────────────────────────────────────────────────────

class AppConfig {
  // Gemini API key — injected via --dart-define=GEMINI_API_KEY=...
  // Falls back to empty string so the app degrades gracefully to offline mode
  // rather than crashing when key is missing.
  static const geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  static const geminiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  static String get geminiUrlWithKey => '$geminiUrl?key=$geminiApiKey';

  /// True when a valid Gemini key is available — used to decide online vs offline path
  static bool get hasGeminiKey => geminiApiKey.isNotEmpty;
}
