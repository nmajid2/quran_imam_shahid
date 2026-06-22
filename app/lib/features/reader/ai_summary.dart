import '../../data/models/surah.dart';
import '../ai/openai_client.dart';
import '../lexicon/lexicon_db.dart';
import '../tafsir/tafsir_db.dart';

final RegExp _arabicWord = RegExp('[ء-ي]');

String _truncate(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max).trimRight()}…';

/// Builds the per-ayah material (Arabic + translation + all-three-editions tafsir +
/// Mufradat word meanings) for a set of ayat, ready to hand to [OpenAiClient].
///
/// Reads the bundled tafsir + lexicon databases (offline). Tafsir is passage-based,
/// so a block spanning several visible ayat is attached only once; Mufradat roots
/// are deduped across the whole selection. Snippets are truncated to bound the prompt.
Future<List<AiAyahMaterial>> gatherAyahMaterial({
  required Surah surah,
  required List<int> ayahNumbers,
  required String lang,
  required TafsirDb tafsirDb,
  required LexiconDb lexiconDb,
}) async {
  final editions = tafsirDb.catalog().editions;
  final seenTafsir = <String>{}; // editionId:start-end — block shown once
  final seenRoots = <String>{}; // mufradat root — entry shown once
  final out = <AiAyahMaterial>[];

  for (final n in ayahNumbers) {
    final ayah = surah.ayat.firstWhere(
      (a) => a.ayah == n,
      orElse: () => Ayah(ayah: n, textAr: '', translations: const {}),
    );
    if (ayah.textAr.isEmpty) continue;

    // Tafsir from each edition (dedupe spanning blocks).
    final tafsir = <AiTafsirSnippet>[];
    for (final e in editions) {
      final c = await tafsirDb.content(e.id, surah.number, n);
      if (c == null) continue;
      final key = '${e.id}:${c.ayahStart}-${c.ayahEnd}';
      if (!seenTafsir.add(key)) continue;
      tafsir.add(AiTafsirSnippet(e.name, e.author, _truncate(c.content, 1200)));
    }

    // Mufradat for each new Arabic word root.
    final mufradat = <AiMufradatSnippet>[];
    final words = ayah.textAr
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && _arabicWord.hasMatch(w));
    for (final w in words) {
      final look = await lexiconDb.lookup(w);
      if (!look.hasEntry || look.root == null) continue;
      if (!seenRoots.add(look.root!)) continue;
      final entry = look.entries.firstWhere(
        (en) => en.bookId == 'mufradat',
        orElse: () => look.entries.first,
      );
      mufradat.add(AiMufradatSnippet(
        w,
        look.root,
        entry.book?.name ?? 'Mufradat',
        _truncate(entry.content, 800),
      ));
    }

    out.add(AiAyahMaterial(
      surah: surah.number,
      ayah: n,
      textAr: ayah.textAr,
      translation: ayah.translation(lang),
      tafsir: tafsir,
      mufradat: mufradat,
    ));
  }
  return out;
}
