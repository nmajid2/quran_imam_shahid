import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persisted theme choice: which preset + light/dark/system.
class ThemeStore {
  static const _storage = FlutterSecureStorage();
  static const _kPreset = 'theme_preset';
  static const _kMode = 'theme_mode';

  static Future<({String preset, ThemeMode mode})> load() async {
    final all = await _storage.readAll();
    final mode = switch (all[_kMode]) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light, // light-first default
    };
    return (preset: all[_kPreset] ?? 'sahar', mode: mode);
  }

  static Future<void> savePreset(String id) =>
      _storage.write(key: _kPreset, value: id);
  static Future<void> saveMode(ThemeMode m) =>
      _storage.write(key: _kMode, value: m.name);
}

/// Active preset id (e.g. 'sahar'). Seeded from storage via override in main().
final presetIdProvider = StateProvider<String>((_) => 'sahar');

/// Light / dark / system. Light-first default.
final themeModeProvider = StateProvider<ThemeMode>((_) => ThemeMode.light);
