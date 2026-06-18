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
}
