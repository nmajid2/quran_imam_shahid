import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Stores recitation audio for offline playback.
///
/// Files live under `<app documents>/audio/<reciterId>/<surah>/<ayah>.mp3`.
/// Download is per-surah on demand: the player streams an ayah from the CDN when
/// its file isn't present, and uses the local file once the surah is downloaded.
class DownloadManager {
  DownloadManager({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  Directory? _root;

  Future<Directory> _audioRoot() async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    _root = Directory('${docs.path}/audio');
    return _root!;
  }

  Future<File> _ayahFile(String reciterId, int surah, int ayah) async {
    final root = await _audioRoot();
    return File('${root.path}/$reciterId/$surah/$ayah.mp3');
  }

  /// Local file path for an ayah if it has been downloaded, else null.
  Future<String?> localPath(String reciterId, int surah, int ayah) async {
    final f = await _ayahFile(reciterId, surah, ayah);
    return await f.exists() ? f.path : null;
  }

  /// True when every ayah of the surah is present on disk for this reciter.
  Future<bool> isSurahDownloaded(
      String reciterId, int surah, int ayahCount) async {
    for (var a = 1; a <= ayahCount; a++) {
      final f = await _ayahFile(reciterId, surah, a);
      if (!await f.exists()) return false;
    }
    return true;
  }

  /// Number of downloaded `.mp3` files per owner (a reciterId for the Arabic, or
  /// `translation_<lang>` for a translation) and surah, by scanning the audio
  /// directory once. Lets the surah list badge each card's offline status.
  Future<Map<String, Map<int, int>>> scanCounts() async {
    final root = await _audioRoot();
    final out = <String, Map<int, int>>{};
    if (!await root.exists()) return out;
    await for (final owner in root.list(followLinks: false)) {
      if (owner is! Directory) continue;
      final ownerName = owner.path.split(Platform.pathSeparator).last;
      final perSurah = <int, int>{};
      await for (final sdir in owner.list(followLinks: false)) {
        if (sdir is! Directory) continue;
        final surah =
            int.tryParse(sdir.path.split(Platform.pathSeparator).last);
        if (surah == null) continue;
        var n = 0;
        await for (final f in sdir.list(followLinks: false)) {
          if (f is File && f.path.endsWith('.mp3')) n++;
        }
        if (n > 0) perSurah[surah] = n;
      }
      out[ownerName] = perSurah;
    }
    return out;
  }

  /// The subset of [urls] (ayah -> CDN URL) whose files aren't on disk yet, so a
  /// download fetches only what's missing.
  Future<Map<int, String>> missingAyat(
      String reciterId, int surah, Map<int, String> urls) async {
    final out = <int, String>{};
    for (final e in urls.entries) {
      final f = await _ayahFile(reciterId, surah, e.key);
      if (!await f.exists()) out[e.key] = e.value;
    }
    return out;
  }

  /// Download every missing ayah for a surah. [urls] maps ayah -> CDN URL.
  /// [onProgress] is called with (done, total) as each file lands.
  Future<void> downloadSurah(
    String reciterId,
    int surah,
    Map<int, String> urls, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final total = urls.length;
    var done = 0;
    for (final entry in urls.entries) {
      if (isCancelled?.call() ?? false) return;
      final file = await _ayahFile(reciterId, surah, entry.key);
      if (!await file.exists()) {
        final resp = await _http.get(Uri.parse(entry.value));
        if (resp.statusCode == 200) {
          await file.parent.create(recursive: true);
          await file.writeAsBytes(resp.bodyBytes);
        } else {
          throw Exception(
              'Download failed for $surah:${entry.key} (${resp.statusCode})');
        }
      }
      done++;
      onProgress?.call(done, total);
    }
  }

  /// Remove a surah's downloaded audio for one reciter (free space).
  Future<void> deleteSurah(String reciterId, int surah) async {
    final root = await _audioRoot();
    final dir = Directory('${root.path}/$reciterId/$surah');
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
