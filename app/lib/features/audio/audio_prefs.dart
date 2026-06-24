import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persisted audio preferences (separate from the AI settings store).
class AudioPrefs {
  static const _storage = FlutterSecureStorage();
  static const _kPlayTranslation = 'play_translation';

  static Future<bool> loadPlayTranslation() async {
    final s = await _storage.read(key: _kPlayTranslation);
    return s == 'true';
  }

  static Future<void> savePlayTranslation(bool v) =>
      _storage.write(key: _kPlayTranslation, value: '$v');
}

/// When on, the reader reads each ayah's TRANSLATION (human audio) right after
/// its Arabic recitation. Only effective for languages that have a translation
/// audio source (fa/en); the player bar hides the toggle otherwise.
final playTranslationProvider = StateProvider<bool>((_) => false);
