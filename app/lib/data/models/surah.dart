/// Plain data models mirroring the gateway's /v1/quran payloads.

class SurahSummary {
  final int number;
  final String nameAr;
  final String nameTranslit;
  final Map<String, String> names;
  final String revelationPlace;
  final int ayahCount;

  SurahSummary({
    required this.number,
    required this.nameAr,
    required this.nameTranslit,
    required this.names,
    required this.revelationPlace,
    required this.ayahCount,
  });

  factory SurahSummary.fromJson(Map<String, dynamic> j) => SurahSummary(
        number: j['number'] as int,
        nameAr: j['name_ar'] as String,
        nameTranslit: j['name_translit'] as String,
        names: Map<String, String>.from(j['names'] as Map),
        revelationPlace: (j['revelation_place'] ?? '') as String,
        ayahCount: j['ayah_count'] as int,
      );

  String localizedName(String lang) => names[lang] ?? nameTranslit;
}

class Ayah {
  final int ayah;
  final String textAr;
  final Map<String, String> translations;

  Ayah({required this.ayah, required this.textAr, required this.translations});

  factory Ayah.fromJson(Map<String, dynamic> j) => Ayah(
        ayah: j['ayah'] as int,
        textAr: j['text_ar'] as String,
        translations: Map<String, String>.from(j['translations'] as Map),
      );

  String translation(String lang) => translations[lang] ?? translations['en'] ?? '';
}

/// One hit from the gateway's full-text ayah search.
class AyahSearchResult {
  final int surah;
  final int ayah;
  final String textAr;
  final String translation;
  final String matched; // 'ar' | 'translation' — which field matched

  AyahSearchResult({
    required this.surah,
    required this.ayah,
    required this.textAr,
    required this.translation,
    required this.matched,
  });

  factory AyahSearchResult.fromJson(Map<String, dynamic> j) => AyahSearchResult(
        surah: j['surah'] as int,
        ayah: j['ayah'] as int,
        textAr: (j['text_ar'] ?? '') as String,
        translation: (j['translation'] ?? '') as String,
        matched: (j['matched'] ?? 'ar') as String,
      );
}

/// The result set for a search query, with the full match count for "showing N of M".
class AyahSearchResponse {
  final int total;
  final bool truncated;
  final List<AyahSearchResult> results;

  AyahSearchResponse(
      {required this.total, required this.truncated, required this.results});

  factory AyahSearchResponse.fromJson(Map<String, dynamic> j) =>
      AyahSearchResponse(
        total: (j['total'] ?? 0) as int,
        truncated: (j['truncated'] ?? false) as bool,
        results: ((j['results'] ?? const []) as List)
            .map((e) => AyahSearchResult.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Surah {
  final int number;
  final String nameAr;
  final String nameTranslit;
  final List<Ayah> ayat;

  Surah({
    required this.number,
    required this.nameAr,
    required this.nameTranslit,
    required this.ayat,
  });

  factory Surah.fromJson(Map<String, dynamic> j) => Surah(
        number: j['number'] as int,
        nameAr: j['name_ar'] as String,
        nameTranslit: j['name_translit'] as String,
        ayat: (j['ayat'] as List)
            .map((e) => Ayah.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
