/// Tafsir models mirroring the gateway's /v1/tafsirs payload (book tafsir — the
/// authentic Shia commentaries, distinct from the AI-grounded /v1/tafsir summary).

class TafsirEdition {
  final String id;
  final String name; // transliterated (original) name
  final String? nameFa;
  final String author;
  final String lang;

  TafsirEdition({
    required this.id,
    required this.name,
    required this.author,
    required this.lang,
    this.nameFa,
  });

  factory TafsirEdition.fromJson(Map<String, dynamic> j) => TafsirEdition(
        id: j['id'] as String,
        name: j['name'] as String,
        nameFa: j['name_fa'] as String?,
        author: j['author'] as String,
        lang: j['lang'] as String,
      );

  String localizedName(String lang) =>
      (lang == 'fa' && nameFa != null) ? nameFa! : name;
}

class TafsirCatalog {
  final String attribution;
  final List<TafsirEdition> editions;

  TafsirCatalog({required this.attribution, required this.editions});

  factory TafsirCatalog.fromJson(Map<String, dynamic> j) => TafsirCatalog(
        attribution: (j['attribution'] ?? '') as String,
        editions: (j['tafsirs'] as List)
            .map((e) => TafsirEdition.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  TafsirEdition? byId(String id) {
    for (final e in editions) {
      if (e.id == id) return e;
    }
    return null;
  }
}

/// One ayah's commentary from a chosen tafsir. These tafsirs are passage-based,
/// so [ayahStart]..[ayahEnd] is the range of ayat this block actually covers.
class TafsirContent {
  final String content; // Markdown
  final String attribution;
  final int ayahStart;
  final int ayahEnd;

  TafsirContent({
    required this.content,
    required this.attribution,
    required this.ayahStart,
    required this.ayahEnd,
  });

  bool get coversMultiple => ayahEnd > ayahStart;

  factory TafsirContent.fromJson(Map<String, dynamic> j) => TafsirContent(
        content: j['content'] as String,
        attribution: (j['attribution'] ?? '') as String,
        ayahStart: (j['ayah_start'] ?? 0) as int,
        ayahEnd: (j['ayah_end'] ?? 0) as int,
      );
}
