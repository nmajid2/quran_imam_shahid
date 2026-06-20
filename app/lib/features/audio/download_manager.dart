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

  /// Download every missing ayah for a surah. [urls] maps ayah -> CDN URL.
  /// [onProgress] is called with (done, total) as each file lands.
  Future<void> downloadSurah(
    String reciterId,
    int surah,
    Map<int, String> urls, {
    void Function(int done, int total)? onProgress,
  }) async {
    final total = urls.length;
    var done = 0;
    for (final entry in urls.entries) {
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
