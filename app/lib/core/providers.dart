import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/surah.dart';
import 'api_client.dart';
import 'config.dart';

/// Single gateway client for the whole app.
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// Current UI / content language (fa | en | nl).
final languageProvider = StateProvider<String>((ref) => AppConfig.defaultLanguage);

/// Surah list (fetched from the gateway; cached for the session).
final surahListProvider = FutureProvider<List<SurahSummary>>((ref) {
  return ref.watch(apiClientProvider).listSurahs();
});

/// A single surah's full text.
final surahProvider = FutureProvider.family<Surah, int>((ref, number) {
  return ref.watch(apiClientProvider).getSurah(number);
});
