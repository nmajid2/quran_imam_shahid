import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../data/models/reciter.dart';
import '../data/models/surah.dart';

/// Arabic diacritics / tatweel — stripped before search matching.
final RegExp _arDiacritics =
    RegExp('[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u0640]');
const Map<String, String> _arFold = {
  'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا',
  'ى': 'ي', 'ئ': 'ي', 'ی': 'ي',
  'ؤ': 'و',
  'ة': 'ه',
  'ک': 'ك',
};

/// Diacritic-insensitive Arabic/Persian folding, used for offline ayah search.
String normalizeArabicForSearch(String s) {
  final buf = StringBuffer();
  for (final ch in s.replaceAll(_arDiacritics, '').split('')) {
    buf.write(_arFold[ch] ?? ch);
  }
  return buf.toString();
}

/// All Quran text + reciter catalog, bundled in the APK and served entirely
/// **on-device** (no gateway). Replaces the former FastAPI content endpoints:
/// surah list/text, full-text search, reciters, and per-ayah audio URLs.
///
/// The Quran is shipped gzipped (`assets/quran/quran.json.gz`, ~1.5 MB) and
/// decoded once into memory on first use. Audio is still streamed/downloaded
/// from EveryAyah, but the URLs are now built locally from the reciter folder.
class LocalContent {
  List<SurahSummary>? _summaries;
  final Map<int, Surah> _surahs = {};
  ReciterCatalog? _reciters;
  final String _audioBase = 'https://everyayah.com/data';
  Future<void>? _loading;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    // Quran (gzipped JSON).
    final gz = await rootBundle.load('assets/quran/quran.json.gz');
    final bytes = gz.buffer.asUint8List(gz.offsetInBytes, gz.lengthInBytes);
    final jsonStr = utf8.decode(gzip.decode(bytes));
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final list = data['surahs'] as List;
    _summaries = [
      for (final e in list) SurahSummary.fromJson(e as Map<String, dynamic>)
    ];
    for (final e in list) {
      final s = Surah.fromJson(e as Map<String, dynamic>);
      _surahs[s.number] = s;
    }

    // Reciter catalog.
    final recStr = await rootBundle.loadString('assets/audio/reciters.json');
    _reciters =
        ReciterCatalog.fromJson(jsonDecode(recStr) as Map<String, dynamic>);
  }

  // ---- Quran ----

  List<SurahSummary> listSurahs() => List.unmodifiable(_summaries ?? const []);

  Surah getSurah(int number) {
    final s = _surahs[number];
    if (s == null) throw StateError('Surah $number not loaded');
    return s;
  }

  // ---- Search (mirrors the old gateway /v1/search) ----

  AyahSearchResponse search(String query, String lang,
      {int? surah, int limit = 100}) {
    final words =
        query.split(RegExp(r'\s+')).where((w) => w.trim().isNotEmpty).toList();
    if (words.isEmpty) {
      return AyahSearchResponse(total: 0, truncated: false, results: const []);
    }
    final arTokens = [
      for (final w in words)
        if (normalizeArabicForSearch(w).isNotEmpty)
          normalizeArabicForSearch(w)
    ];
    final faLang = lang == 'fa';
    final trTokens = faLang
        ? arTokens
        : [for (final w in words) w.toLowerCase()];

    final scope = surah != null
        ? [if (_surahs[surah] != null) _surahs[surah]!]
        : (_summaries ?? const []).map((s) => _surahs[s.number]!).toList();

    final results = <AyahSearchResult>[];
    var total = 0;
    for (final s in scope) {
      for (final a in s.ayat) {
        final arHay = normalizeArabicForSearch(a.textAr);
        final arMatch =
            arTokens.isNotEmpty && arTokens.every((t) => arHay.contains(t));
        final tr = a.translation(lang);
        final trHay = tr.isEmpty
            ? ''
            : (faLang ? normalizeArabicForSearch(tr) : tr.toLowerCase());
        final trMatch = tr.isNotEmpty &&
            trTokens.isNotEmpty &&
            trTokens.every((t) => trHay.contains(t));
        if (!arMatch && !trMatch) continue;
        total++;
        if (results.length < limit) {
          results.add(AyahSearchResult(
            surah: s.number,
            ayah: a.ayah,
            textAr: a.textAr,
            translation: tr,
            matched: arMatch ? 'ar' : 'translation',
          ));
        }
      }
    }
    return AyahSearchResponse(
        total: total, truncated: total > results.length, results: results);
  }

  // ---- Audio ----

  ReciterCatalog reciters() =>
      _reciters ?? ReciterCatalog(defaultId: '', reciters: const []);

  String _pad3(int n) => n.toString().padLeft(3, '0');

  /// Per-ayah MP3 URL for one ayah (EveryAyah scheme), or null if unknown reciter.
  String? audioUrl(String reciterId, int surah, int ayah) {
    final r = _reciters?.byId(reciterId);
    if (r == null) return null;
    return '$_audioBase/${r.folder}/${_pad3(surah)}${_pad3(ayah)}.mp3';
  }

  /// Whether a human-recited translation audio exists for [lang] (fa/en).
  bool hasTranslationAudio(String lang) =>
      _reciters?.translationFor(lang) != null;

  /// Per-ayah MP3 URL for the TRANSLATION recitation in [lang] (same EveryAyah
  /// scheme), or null if there's no translation audio for that language.
  String? translationAudioUrl(String lang, int surah, int ayah) {
    final t = _reciters?.translationFor(lang);
    if (t == null) return null;
    return '$_audioBase/${t.folder}/${_pad3(surah)}${_pad3(ayah)}.mp3';
  }

  /// All per-ayah TRANSLATION URLs for a surah (offline downloader), or empty
  /// when [lang] has no translation audio.
  Map<int, String> surahTranslationAudioUrls(String lang, int surah) {
    final t = _reciters?.translationFor(lang);
    final s = _surahs[surah];
    if (t == null || s == null) return {};
    return {
      for (final a in s.ayat)
        a.ayah: '$_audioBase/${t.folder}/${_pad3(surah)}${_pad3(a.ayah)}.mp3'
    };
  }

  /// All per-ayah URLs for a surah (offline downloader / full-surah play).
  Map<int, String> surahAudioUrls(String reciterId, int surah) {
    final r = _reciters?.byId(reciterId);
    final s = _surahs[surah];
    if (r == null || s == null) return {};
    return {
      for (final a in s.ayat)
        a.ayah: '$_audioBase/${r.folder}/${_pad3(surah)}${_pad3(a.ayah)}.mp3'
    };
  }
}
