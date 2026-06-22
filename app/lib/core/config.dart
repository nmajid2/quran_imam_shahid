/// App configuration. The gateway base URL + device token point the app at YOUR box.
///
/// Override at build time, e.g.:
///   flutter run --dart-define=GATEWAY_URL=https://quran.example.ts.net \
///               --dart-define=DEVICE_TOKEN=xxxx
class AppConfig {
  static const String gatewayUrl = String.fromEnvironment(
    'GATEWAY_URL',
    defaultValue: 'http://localhost:8077',
  );

  /// In production this is read from secure storage, not a dart-define.
  static const String deviceTokenFallback = String.fromEnvironment(
    'DEVICE_TOKEN',
    defaultValue: 'dev-token-change-me',
  );

  /// Supported UI / content languages.
  static const List<String> languages = ['fa', 'en', 'nl'];
  static const String defaultLanguage = 'en';

  /// OpenAI key for the in-app AI tafsir summary. The app calls OpenAI directly
  /// (no gateway) for this feature, so the key is baked in at build time:
  ///   flutter run --dart-define=OPENAI_API_KEY=sk-...
  /// Empty → the AI summary button explains it needs to be configured.
  static const String openAiApiKey =
      String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');

  /// Selectable OpenAI models for the AI summary (first is the default).
  static const List<String> aiModels = [
    'gpt-4o-mini',
    'gpt-5.4-mini',
    'gpt-5-mini',
    'gpt-4o',
    'gpt-5.1',
  ];
  static const String defaultAiModel = 'gpt-4o-mini';
}
