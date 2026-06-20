import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/surah.dart';
import '../data/models/tafsir.dart';
import '../features/lexicon/lexicon_db.dart';
import '../features/tafsir/tafsir_db.dart';
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

/// Tafsir engine — reads the tafsir databases bundled inside the app (offline,
/// no gateway). Extracts each edition on first use.
final tafsirDbProvider = Provider<TafsirDb>((ref) => TafsirDb());

/// Available book tafsirs (al-Mizan, Nemooneh, Noor — authentic Shia sources).
final tafsirsProvider = FutureProvider<TafsirCatalog>((ref) async {
  return ref.watch(tafsirDbProvider).catalog();
});

/// The tafsir the user has chosen to read. Null until set; the UI falls back to
/// the first edition. Persists across ayat for the session.
final selectedTafsirProvider = StateProvider<String?>((ref) => null);

/// One ayah's commentary from a chosen tafsir, read from the bundled database.
typedef TafsirKey = ({String id, int surah, int ayah});
final tafsirContentProvider =
    FutureProvider.family<TafsirContent, TafsirKey>((ref, k) async {
  final c = await ref.watch(tafsirDbProvider).content(k.id, k.surah, k.ayah);
  if (c == null) throw Exception('No commentary for ${k.surah}:${k.ayah}');
  return c;
});

/// Lexicon engine — bundled word→root index + Mufradat entries (offline).
final lexiconDbProvider = Provider<LexiconDb>((ref) => LexiconDb());

/// Lexicon lookup for a tapped Quran word (root + entries).
final lexiconLookupProvider =
    FutureProvider.family<LexiconLookup, String>((ref, word) {
  return ref.watch(lexiconDbProvider).lookup(word);
});
