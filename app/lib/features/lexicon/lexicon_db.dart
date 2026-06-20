import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Arabic normalization — MUST stay byte-identical to the Python `norm()` used to
/// build `word_root.form` in lexicon.db (tools/lexicon/build_wordroot.py).
final RegExp _harakat = RegExp(
    '[ؐ-ؚـً-ٟۖ-ۭ࣓-ࣿ]');
String normalizeArabic(String t) {
  t = t.replaceAll('ٰ', 'ا'); // dagger alef -> alef
  t = t.replaceAll(_harakat, '');
  t = t
      .replaceAll('ٱ', 'ا') // alef wasla
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي') // alef maksura -> ya
      .replaceAll('ة', 'ه'); // ta marbuta -> ha
  return t.trim();
}

/// A lexicon edition (book). Mufradat ships now; al-Tahqiq drops in later.
class LexiconBook {
  final String id; // matches entry.book in the DB
  final String name; // transliterated
  final String nameFa;
  final String author;
  const LexiconBook(this.id, this.name, this.nameFa, this.author);
}

const List<LexiconBook> lexiconBooks = [
  LexiconBook('mufradat', 'Mufradat', 'مفردات', 'Raghib al-Isfahani'),
  // LexiconBook('tahqiq', 'al-Tahqiq', 'التحقيق', 'Hasan Mostafavi'),  // when provided
];

class LexiconEntry {
  final String bookId;
  final String content;
  LexiconEntry(this.bookId, this.content);
  LexiconBook? get book =>
      lexiconBooks.where((b) => b.id == bookId).cast<LexiconBook?>().firstWhere(
            (b) => true,
            orElse: () => null,
          );
}

class LexiconLookup {
  final String word;
  final String? root;
  final List<LexiconEntry> entries;
  LexiconLookup(this.word, this.root, this.entries);
  bool get hasEntry => root != null && entries.isNotEmpty;
}

/// Reads the bundled lexicon (word→root index + per-root entries) via sqflite.
/// The gzipped DB asset is inflated to app docs on first use.
class LexiconDb {
  static const _assetGz = 'assets/lexicon/lexicon.db.gz';
  static const _fileName = 'lexicon_v1.db';
  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final docs = await getApplicationDocumentsDirectory();
    final path = '${docs.path}/$_fileName';
    final file = File(path);
    if (!await file.exists()) {
      final gz = (await rootBundle.load(_assetGz)).buffer.asUint8List();
      final bytes = gzip.decode(gz);
      await file.writeAsBytes(bytes, flush: true);
    }
    _db = await openReadOnlyDatabase(path);
    return _db!;
  }

  Future<String?> rootForWord(String word) async {
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT root FROM word_root WHERE form=? LIMIT 1',
      [normalizeArabic(word)],
    );
    return rows.isEmpty ? null : rows.first['root'] as String?;
  }

  Future<LexiconLookup> lookup(String word) async {
    final root = await rootForWord(word);
    if (root == null) return LexiconLookup(word, null, const []);
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT book, content FROM entry WHERE root=?',
      [root],
    );
    final entries = rows
        .map((m) => LexiconEntry(m['book'] as String, m['content'] as String))
        .toList();
    return LexiconLookup(word, root, entries);
  }
}
