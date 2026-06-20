import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import '../data/models/reciter.dart';
import '../data/models/surah.dart';

/// The ONLY thing that talks to the gateway. The app never calls AI/speech
/// providers directly and never holds their keys.
class ApiClient {
  ApiClient({http.Client? client, String? token})
      : _http = client ?? http.Client(),
        _token = token ?? AppConfig.deviceTokenFallback;

  final http.Client _http;
  final String _token;

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      };

  Uri _u(String path) => Uri.parse('${AppConfig.gatewayUrl}$path');

  Future<bool> health() async {
    final r = await _http.get(_u('/healthz'));
    return r.statusCode == 200;
  }

  Future<List<SurahSummary>> listSurahs() async {
    final r = await _http.get(_u('/v1/quran'), headers: _authHeaders);
    _ensureOk(r);
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return (data['surahs'] as List)
        .map((e) => SurahSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Surah> getSurah(int number) async {
    final r = await _http.get(_u('/v1/quran/$number'), headers: _authHeaders);
    _ensureOk(r);
    return Surah.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// The catalog of reciters the user can choose from.
  Future<ReciterCatalog> listReciters() async {
    final r = await _http.get(_u('/v1/reciters'), headers: _authHeaders);
    _ensureOk(r);
    return ReciterCatalog.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Per-ayah audio URLs for a whole surah (used for playback + offline download).
  /// Returns a map of ayah number -> MP3 URL.
  Future<Map<int, String>> surahAudioUrls(String reciterId, int surah) async {
    final r = await _http.get(
      _u('/v1/audio/$reciterId/$surah'),
      headers: _authHeaders,
    );
    _ensureOk(r);
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return {
      for (final e in (data['urls'] as List))
        (e as Map<String, dynamic>)['ayah'] as int: e['url'] as String,
    };
  }

  Future<Map<String, dynamic>> tafsir(int surah, int ayah, String lang) async {
    final r = await _http.post(
      _u('/v1/tafsir'),
      headers: _authHeaders,
      body: jsonEncode({'surah': surah, 'ayah': ayah, 'lang': lang}),
    );
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> ask(String text, String lang,
      {int? surah, int? ayah}) async {
    final body = <String, dynamic>{'text': text, 'lang': lang};
    if (surah != null && ayah != null) {
      body['ayah_ref'] = {'surah': surah, 'ayah': ayah};
    }
    final r = await _http.post(_u('/v1/ask'),
        headers: _authHeaders, body: jsonEncode(body));
    _ensureOk(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  void _ensureOk(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ApiException(r.statusCode, r.body);
    }
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'ApiException($statusCode): $body';
}
