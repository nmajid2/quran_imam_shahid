import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/models/tafsir.dart';

const _kAttribution = 'Tafsir data © Furqan Apps (furqan.app), CC BY-ND 4.0.';

/// One embedded tafsir: where its archive lives, the .db inside it, and the
/// Persian content column. All authentic, human-authored, Persian editions.
class _Edition {
  final String id;
  final String name; // transliterated (original) name
  final String nameFa;
  final String author;
  final String asset; // bundled .tar.xz
  final String dbFile; // the .db inside the archive
  final String column; // Persian content column
  const _Edition(this.id, this.name, this.nameFa, this.author, this.asset,
      this.dbFile, this.column);
}

const List<_Edition> _editions = [
  _Edition('almizan', 'Al-Mizan', 'المیزان', 'Allamah Tabatabai',
      'assets/tafsir/tafsir_almizan_fa.db.tar.xz', 'tafsir_almizan_fa.db', 'content'),
  _Edition('nemooneh', 'Nemooneh', 'نمونه', 'Makarem Shirazi',
      'assets/tafsir/tafsir_nemouneh_fa_en_ur.tar.xz', 'tafsir_namouneh.db', 'content'),
  _Edition('noor', 'Noor', 'نور', 'Mohsen Qaraati',
      'assets/tafsir/tafsir-noor.tar.xz', 'tafsir-noor.db', 'content_fa'),
];

/// Reads tafsir entirely from data bundled inside the app — no gateway needed.
/// On first access of an edition, its `.db` is extracted from the bundled
/// `.tar.xz` (in a background isolate) into the app's documents dir, then opened
/// read-only and queried with sqflite.
class TafsirDb {
  final Map<String, Database> _open = {};
  final Map<String, Future<Database>> _opening = {};

  TafsirCatalog catalog() => TafsirCatalog(
        attribution: _kAttribution,
        editions: _editions
            .map((e) => TafsirEdition(
                id: e.id,
                name: e.name,
                nameFa: e.nameFa,
                author: e.author,
                lang: 'fa'))
            .toList(),
      );

  Future<Directory> _dbDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/tafsir_db');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Database> _db(String id) async {
    final existing = _open[id];
    if (existing != null) return existing;
    // De-dupe concurrent first-time opens (extraction is expensive).
    return _opening.putIfAbsent(id, () async {
      final db = await _prepare(id);
      _open[id] = db;
      _opening.remove(id);
      return db;
    });
  }

  Future<Database> _prepare(String id) async {
    final e = _editions.firstWhere((x) => x.id == id);
    final dir = await _dbDir();
    final path = '${dir.path}/${e.dbFile}';
    final file = File(path);
    if (!await file.exists()) {
      final xz = (await rootBundle.load(e.asset)).buffer.asUint8List();
      final bytes = await compute(_extractDb, (xz: xz, db: e.dbFile));
      await file.writeAsBytes(bytes, flush: true);
    }
    return openReadOnlyDatabase(path);
  }

  Future<TafsirContent?> content(String id, int surah, int ayah) async {
    final e = _editions.firstWhere((x) => x.id == id);
    final db = await _db(id);
    final m = await db.rawQuery(
      'SELECT content_id FROM ayah_mapping WHERE surah_number=? AND ayah_number=?',
      [surah, ayah],
    );
    if (m.isEmpty) return null;
    final cid = m.first['content_id'];
    final c = await db.rawQuery(
      'SELECT ${e.column} AS c FROM content WHERE content_id=?',
      [cid],
    );
    if (c.isEmpty || c.first['c'] == null) return null;
    final r = await db.rawQuery(
      'SELECT MIN(ayah_number) AS s, MAX(ayah_number) AS e '
      'FROM ayah_mapping WHERE surah_number=? AND content_id=?',
      [surah, cid],
    );
    return TafsirContent(
      content: c.first['c'] as String,
      attribution: _kAttribution,
      ayahStart: (r.first['s'] as int?) ?? ayah,
      ayahEnd: (r.first['e'] as int?) ?? ayah,
    );
  }
}

/// Runs in a background isolate: xz-decompress → untar → return the .db bytes.
Uint8List _extractDb(({Uint8List xz, String db}) req) {
  final tarBytes = XZDecoder().decodeBytes(req.xz);
  final archive = TarDecoder().decodeBytes(tarBytes);
  for (final f in archive.files) {
    if (f.isFile && f.name.split('/').last == req.db) {
      return Uint8List.fromList(f.content as List<int>);
    }
  }
  throw Exception('${req.db} not found in archive');
}
