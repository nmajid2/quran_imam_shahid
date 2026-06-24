import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import 'ai_usage.dart';

/// A tafsir snippet from one edition for one ayah, fed to the AI.
class AiTafsirSnippet {
  final String edition;
  final String author;
  final String text;
  const AiTafsirSnippet(this.edition, this.author, this.text);
}

/// A Mufradat (word-root) entry for a word in an ayah, fed to the AI.
class AiMufradatSnippet {
  final String word;
  final String? root;
  final String book;
  final String text;
  const AiMufradatSnippet(this.word, this.root, this.book, this.text);
}

/// Everything we know about one ayah, bundled for the AI to summarize.
class AiAyahMaterial {
  final int surah;
  final int ayah;
  final String textAr;
  final String? translation;
  final List<AiTafsirSnippet> tafsir;
  final List<AiMufradatSnippet> mufradat;
  const AiAyahMaterial({
    required this.surah,
    required this.ayah,
    required this.textAr,
    this.translation,
    this.tafsir = const [],
    this.mufradat = const [],
  });
}

/// Round-1 result: a short summary, key points, and up to 5 study questions the
/// reader can tap to ask about the ayat.
class AiSummary {
  final String summary;
  final List<String> keyPoints;
  final List<String> questions;
  const AiSummary(this.summary, this.keyPoints, this.questions);
}

/// Round-2 result: the answer to a selected question, an optional clarifying
/// example (only when the concept is confusing), plus any (optional) new follow-up
/// questions.
///
/// [inScope] is true when the answer is fully supported by the provided tafsir /
/// Mufradat material; false when the model had to draw on outside knowledge — in
/// which case [references] carries the sources it cited for that answer.
class AiAnswer {
  final String answer;
  final String? example;
  final List<String> questions;
  final bool inScope;
  final List<String> references;
  const AiAnswer(
    this.answer,
    this.example,
    this.questions, {
    this.inScope = true,
    this.references = const [],
  });
}

/// One prior Q&A turn, re-sent to the stateless model as context.
typedef AiTurn = ({String question, String answer});

/// A Quran ayah the model judged relevant to a free-form question (home "ask").
typedef AiAyahRef = ({int surah, int ayah});

/// Round-0 result for the home "ask the Quran" flow: the ayat the model judged
/// relevant, plus a short note. The app then gathers those ayat's tafsir/Mufradat
/// and calls [OpenAiClient.answer] to compose the grounded final reply.
class AiLocateResult {
  final List<AiAyahRef> ayat;
  final String note;
  const AiLocateResult(this.ayat, this.note);
}

/// Thrown for any AI failure (missing key, HTTP error, unparseable output) so the
/// UI can show a friendly message + retry.
class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Calls the OpenAI Chat Completions API **directly** from the app (no gateway).
///
/// The model is stateless, so every call re-sends the full ayah material; round-2
/// [answer] additionally re-sends the suggested questions, the prior Q&A, and the
/// selected question. Handles both classic models (gpt-4o*, which take `temperature`
/// + JSON mode) and the reasoning families (gpt-5.x / o-series, which reject
/// `temperature` and use `reasoning_effort`). Replies are parsed defensively.
class OpenAiClient {
  OpenAiClient({http.Client? client, String? apiKey})
      : _http = client ?? http.Client(),
        _apiKey = apiKey ?? AppConfig.openAiApiKey;

  final http.Client _http;
  final String _apiKey;

  static final Uri _endpoint =
      Uri.parse('https://api.openai.com/v1/chat/completions');

  static const _langNames = {
    'fa': 'Persian (Farsi)',
    'en': 'English',
    'nl': 'Dutch'
  };

  /// Round 1: summarize the ayat + return up to 5 study questions.
  Future<AiSummary> summarize({
    required String model,
    required String lang,
    required List<AiAyahMaterial> ayat,
    List<AiCallUsage>? usage,
  }) async {
    final data = await _chatJson(model, _summarySystem(lang), _material(ayat),
        usage: usage);
    final summary = (data['summary'] as String?)?.trim() ?? '';
    final points = _stringList(data['key_points'], 6);
    final questions = _stringList(data['questions'], 5);
    if (summary.isEmpty && points.isEmpty) {
      throw AiException('The AI response was empty.');
    }
    return AiSummary(summary, points, questions);
  }

  /// Round 0 (home "ask the Quran"): given a free-form [question], identify the
  /// Quran ayat most relevant to it. Returns up to ~6 refs (most relevant first)
  /// plus a short note; an empty list means the model found nothing relevant.
  Future<AiLocateResult> locateAyat({
    required String model,
    required String lang,
    required String question,
    int? surah, // when set, restrict the located ayat to this surah
    List<AiTurn> history = const [], // prior turns, to resolve follow-up context
    List<AiCallUsage>? usage,
  }) async {
    final b = StringBuffer();
    if (history.isNotEmpty) {
      b.writeln('CONVERSATION SO FAR (for context — resolve what the latest '
          'question refers to):');
      for (final h in history) {
        b.writeln('Q: ${h.question}');
        b.writeln('A: ${h.answer}');
      }
      b.writeln();
    }
    b.write('QUESTION: ${question.trim()}');
    final data = await _chatJson(model, _locateSystem(lang, surah), b.toString(),
        usage: usage);
    final raw = data['ayat'];
    final refs = <AiAyahRef>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final s = _asInt(e['surah']);
        final a = _asInt(e['ayah']);
        if (s == null || a == null) continue;
        if (s < 1 || s > 114 || a < 1) continue;
        if (surah != null && s != surah) continue; // enforce the scope
        if (refs.any((r) => r.surah == s && r.ayah == a)) continue;
        refs.add((surah: s, ayah: a));
        if (refs.length >= 8) break;
      }
    }
    final note = (data['note'] as String?)?.trim() ?? '';
    return AiLocateResult(refs, note);
  }

  static int? _asInt(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));

  /// Classify a free-form (typed or spoken) request into a structured command the
  /// app can execute. Returns the raw JSON map; the caller parses it through the
  /// fixed allow-list (unknown intents are dropped, never executed).
  Future<Map<String, dynamic>> routeCommand({
    required String model,
    required String lang,
    required String text,
    List<AiCallUsage>? usage,
  }) async {
    return _chatJson(model, _commandSystem(lang), 'REQUEST: ${text.trim()}',
        usage: usage);
  }

  String _commandSystem(String lang) {
    final langName = _langNames[lang] ?? 'English';
    return 'You convert a user\'s request about a Quran app into ONE structured '
        'command. The request may be a navigation/playback command, a search, or a '
        'question. Map surah NAMES to their number (1–114), e.g. "Yā-Sīn"/"یس"=36, '
        '"al-Baqarah"/"بقره"=2, "the Cow"=2. '
        'Choose exactly one "intent": '
        '"open_surah" (open/go to a surah, optionally at an ayah); '
        '"recite" (play/recite OUT LOUD — for ONE specific ayah ("read ayah 5", '
        '"recite verse 3") set "ayah" and leave "from_ayah" null so it stops '
        'after that ayah; for a whole surah or "from ayah X onward" set '
        '"from_ayah" (null = from the start) and leave "ayah" null so it keeps '
        'playing; when the user asks to RECITE/READ/PLAY an ayah described by its '
        'MEANING or content with NO surah/number ("read the ayah that says/about '
        'X", "recite the verse about patience") keep intent "recite", leave '
        'surah/ayah/from_ayah null, and put that meaning/description in "query" — '
        'do NOT use search_quran for a recite/read/play request); '
        '"search_quran" (a LITERAL lookup — find where a specific WORD, NAME, or '
        'exact phrase that the user names appears across the whole Quran, e.g. '
        '«آیاتی که واژهٔ صبر در آن آمده», «آیاتی که نام سلیمان آمده», "ayat '
        'containing the word X", "where does the name X appear"; never for '
        'recite/read/play, and NEVER for a request described by MEANING or phrased '
        'as a question — that is "ask"); '
        '"search_in_surah" (the same literal lookup, but within one surah); '
        'For BOTH search intents, set "query" to ONLY the essential Quranic '
        'word(s) or name to match — strip honorifics («حضرت», «علیه‌السلام», '
        '«ع»), titles («پیامبر», «نبی», «حضرت»), and all instruction/filler words '
        '(«تمام آیاتی که در آن از … نام برده شده را نشان بده», "show all ayat that '
        'mention", "where is"). Keep just the core term as it appears in the '
        'Quran; e.g. «تمام آیاتی که از حضرت سلیمان نام برده شده» → query «سلیمان», '
        '"verses that talk about patience" → query "patience". '
        '"open_tafsir" (show the tafsir/commentary of a specific ayah); '
        '"ask" (a question to be answered (why/what/how/meaning), OR a request to '
        'FIND/identify the ayah(s) that SAY, EXPLAIN, PROVE, REFUTE, or address a '
        'matter described by its MEANING/content — e.g. «کدام آیه می‌گوید/'
        'می‌فرماید که …», «آیه‌ای که ثابت می‌کند …», «آیه‌ای که دربارهٔ … توضیح '
        'می‌دهد», "which verse says/explains …", "find the ayah about how …". Put '
        'the user\'s full request in "question"; the app then locates the right '
        'ayat by meaning and explains them. DISTINGUISH from search: a single '
        'literal word/name to match → search_quran; a whole statement/meaning or a '
        '"which ayah says/explains …" request → ask); '
        '"none" (not understood or unsupported). '
        'For "ask", also set "scope_guess": "in_tafsir" if it is about the meaning/'
        'commentary of specific ayat, "outside" if it needs broader Islamic '
        'knowledge (history, fiqh, hadith, comparisons), else "unknown". '
        'Also set "tafsir_only": true when the user RESTRICTS the answer to the '
        'Quran and/or the provided tafsir — i.e. asks for a Quran ayah or to '
        'answer from the Quran/tafsir, e.g. «آیهٔ قرآن که … را نشان بده», «کدام آیه '
        'از قرآن …», «از قرآن/از تفسیر پاسخ بده», "show the Quran ayah that …", '
        '"answer from the Quran/tafsir", "according to the Quran". Set it false '
        'for an open question that does not restrict the source. '
        'The "say" field is a SHORT confirmation in $langName (e.g. "Opening Yā-Sīn '
        'from ayah 5"). '
        'Reply as STRICT JSON with exactly these keys (use null when not relevant): '
        '"intent" (string), "surah" (int|null), "from_ayah" (int|null), '
        '"ayah" (int|null), "query" (string|null), "question" (string|null), '
        '"scope_guess" (string|null), "tafsir_only" (true|false), "say" (string), '
        '"confidence" ("high"|"low"). No other text.';
  }

  /// The in-scope ATTEMPT: answer the question USING ONLY [ayat] (tafsir/Mufradat)
  /// + prior conversation. Returns `inScope == true` with the answer when the
  /// material covers it; `inScope == false` (with a short "not covered" note) when
  /// it does not — never using outside knowledge. The caller decides what to do
  /// with an out-of-scope result (per the out-of-tafsir mode).
  Future<AiAnswer> answer({
    required String model,
    required String lang,
    required List<AiAyahMaterial> ayat,
    required String question,
    String? summary,
    List<String> suggestedQuestions = const [],
    List<AiTurn> history = const [],
    String? beyondDraft, // an out-of-tafsir answer to comment on, if any
    List<AiCallUsage>? usage,
  }) async {
    final user = _answerUser(
      ayat: ayat,
      summary: summary,
      suggestedQuestions: suggestedQuestions,
      history: history,
      question: question,
      beyondDraft: beyondDraft,
    );
    // Larger budget: every answer now carries word-root + grammar analysis.
    final data = await _chatJson(model, _attemptSystem(lang), user,
        maxTokens: 3000, usage: usage);
    final ans = (data['answer'] as String?)?.trim() ?? '';
    final exampleRaw = (data['example'] as String?)?.trim();
    final example =
        (exampleRaw == null || exampleRaw.isEmpty) ? null : exampleRaw;
    final followUps = _stringList(data['questions'], 3);
    // Defaults to in-scope when the key is missing/malformed.
    final inScope = data['in_scope'] is bool
        ? data['in_scope'] as bool
        : data['in_scope']?.toString().toLowerCase().trim() != 'false';
    final references = _stringList(data['references'], 6);
    if (ans.isEmpty) throw AiException('The AI gave no answer.');
    return AiAnswer(ans, example, followUps,
        inScope: inScope, references: references);
  }

  /// Answer a question that is OUT of the tafsir's scope, from authentic Shia
  /// scholarship. The model gets ONLY the bare [question] (+ prior [history]) —
  /// no ayah/tafsir/surah context — and must cite precise references. Always
  /// returns `inScope == false`.
  Future<AiAnswer> answerBeyond({
    required String model,
    required String lang,
    required String question,
    List<AiTurn> history = const [],
    List<AiCallUsage>? usage,
  }) async {
    final b = StringBuffer();
    if (history.isNotEmpty) {
      b.writeln('CONVERSATION SO FAR:');
      for (final h in history) {
        b.writeln('Q: ${h.question}');
        b.writeln('A: ${h.answer}');
      }
      b.writeln();
    }
    b.writeln('QUESTION: $question');
    final data = await _chatJson(
        model, _beyondSystem(lang), b.toString().trim(),
        usage: usage);
    final ans = (data['answer'] as String?)?.trim() ?? '';
    final exampleRaw = (data['example'] as String?)?.trim();
    final example =
        (exampleRaw == null || exampleRaw.isEmpty) ? null : exampleRaw;
    final followUps = _stringList(data['questions'], 3);
    final references = _stringList(data['references'], 8);
    if (ans.isEmpty) throw AiException('The AI gave no answer.');
    return AiAnswer(ans, example, followUps,
        inScope: false, references: references);
  }

  /// Transcribe a recorded audio file to text via OpenAI (Whisper). [lang] is an
  /// ISO-639-1 code (fa/en/nl) used as the source-language hint for accuracy.
  Future<String> transcribe({
    required String filePath,
    required String lang,
  }) async {
    if (_apiKey.trim().isEmpty) {
      throw AiException(
          'OpenAI key not configured. Rebuild with --dart-define=OPENAI_API_KEY=sk-…');
    }
    final req = http.MultipartRequest(
        'POST', Uri.parse('https://api.openai.com/v1/audio/transcriptions'))
      ..headers['Authorization'] = 'Bearer $_apiKey'
      ..fields['model'] = 'whisper-1'
      ..fields['language'] = lang
      ..fields['response_format'] = 'json'
      ..files.add(await http.MultipartFile.fromPath('file', filePath));
    http.StreamedResponse streamed;
    try {
      streamed = await _http.send(req);
    } catch (e) {
      throw AiException('Could not reach OpenAI: $e');
    }
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AiException(
          'Transcription error ${resp.statusCode}: ${_short(resp.body)}');
    }
    final data = _parseJsonObject(utf8.decode(resp.bodyBytes));
    final text = (data?['text'] as String?)?.trim() ?? '';
    return text;
  }

  /// Clean up a raw speech-to-text [text] against the Quran/Islamic context —
  /// fixing misrecognized words, spelling and punctuation WITHOUT changing the
  /// user's meaning. Falls back to the original text on any failure so a voice
  /// question is never lost.
  Future<String> refineTranscript({
    required String model,
    required String lang,
    required String text,
    List<AiCallUsage>? usage,
  }) async {
    if (text.trim().isEmpty) return text;
    try {
      final data = await _chatJson(
          model, _refineSystem(lang), 'TRANSCRIPT: $text',
          usage: usage);
      final q = (data['question'] as String?)?.trim();
      return (q == null || q.isEmpty) ? text : q;
    } catch (_) {
      return text;
    }
  }

  /// Synthesize [text] to speech (OpenAI TTS) with the chosen [voice]. Returns
  /// the raw MP3 bytes. Text is capped to OpenAI's input limit.
  Future<List<int>> synthesizeSpeech({
    required String voice,
    required String text,
    double speed = 1.0,
    String model = AppConfig.ttsModel,
  }) async {
    if (_apiKey.trim().isEmpty) {
      throw AiException(
          'OpenAI key not configured. Rebuild with --dart-define=OPENAI_API_KEY=sk-…');
    }
    final input = text.trim().length > AppConfig.ttsMaxChars
        ? text.trim().substring(0, AppConfig.ttsMaxChars)
        : text.trim();
    if (input.isEmpty) throw AiException('Nothing to read.');
    final resp = await _postWithRetry(
      Uri.parse('https://api.openai.com/v1/audio/speech'),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'voice': voice,
        'input': input,
        'response_format': 'mp3',
        'speed': speed,
      }),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AiException('TTS error ${resp.statusCode}: ${_short(resp.body)}');
    }
    return resp.bodyBytes;
  }

  // ---- request ----

  /// POST with automatic retries for transient failures: dropped/reset
  /// connections and timeouts (a fresh attempt opens a new connection, which
  /// fixes stale keep-alive "Connection reset by peer"), plus 429/5xx. Each
  /// attempt has its own timeout. The final failure surfaces as an [AiException].
  Future<http.Response> _postWithRetry(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
    int maxAttempts = 3,
    Duration timeout = const Duration(seconds: 75),
  }) async {
    for (var attempt = 1;; attempt++) {
      http.Response resp;
      try {
        resp = await _http
            .post(uri, headers: headers, body: body)
            .timeout(timeout);
      } catch (e) {
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        throw AiException('Could not reach OpenAI: $e');
      }
      // Retry transient server responses (rate limit / server errors).
      if ((resp.statusCode == 429 || resp.statusCode >= 500) &&
          attempt < maxAttempts) {
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
        continue;
      }
      return resp;
    }
  }

  /// Append this response's token usage to [usage], if a collector was given.
  void _recordUsage(String body, String model, List<AiCallUsage>? usage) {
    if (usage == null) return;
    try {
      final root = jsonDecode(body) as Map<String, dynamic>;
      final u = root['usage'];
      if (u is! Map) return;
      final inTok = _asInt(u['prompt_tokens']) ?? 0;
      final outTok = _asInt(u['completion_tokens']) ?? 0;
      final details = u['prompt_tokens_details'];
      final cached =
          details is Map ? (_asInt(details['cached_tokens']) ?? 0) : 0;
      if (inTok > 0 || outTok > 0) {
        usage.add(AiCallUsage(
            model: model,
            inputTokens: inTok,
            cachedTokens: cached,
            outputTokens: outTok));
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _chatJson(String model, String system, String user,
      {int maxTokens = 1800, List<AiCallUsage>? usage}) async {
    if (_apiKey.trim().isEmpty) {
      throw AiException(
          'OpenAI key not configured. Rebuild with --dart-define=OPENAI_API_KEY=sk-…');
    }
    final body = <String, dynamic>{
      'model': model,
      'max_completion_tokens': maxTokens,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
    };
    if (_isReasoningModel(model)) {
      body['reasoning_effort'] = _lowestReasoningEffort(model);
    } else {
      body['temperature'] = 0.2;
      body['response_format'] = {'type': 'json_object'};
    }

    final resp = await _postWithRetry(
      _endpoint,
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AiException('OpenAI error ${resp.statusCode}: ${_short(resp.body)}');
    }
    _recordUsage(resp.body, model, usage);
    final content = _extractContent(resp.body);
    if (content == null) throw AiException('OpenAI returned no content.');
    final data = _parseJsonObject(content);
    if (data == null) throw AiException('Could not parse the AI response.');
    return data;
  }

  // ---- prompts ----

  String _summarySystem(String lang) {
    final langName = _langNames[lang] ?? 'English';
    return 'You are a careful Shia Quran study assistant. You are given, for one or '
        'more ayat, their Arabic text, a translation, authentic Shia book-tafsir '
        'excerpts (al-Mizan, Nemooneh, Noor), and Mufradat (word-root) entries. '
        'Summarize ONLY this provided material into a short, clear explanation a '
        'general reader can understand, and when Mufradat (word-root) entries are '
        'given, INCORPORATE the root meaning of the key words into the summary / '
        'key points. Do NOT invent tafsir or hadith beyond what '
        'is given. Do NOT issue any fiqh ruling or fatwa — defer those to a '
        'qualified marja\'. Write entirely in $langName. '
        'Reply as STRICT JSON with exactly these keys: '
        '"summary" (a string, 2–4 short paragraphs), '
        '"key_points" (an array of 3–6 short strings), and '
        '"questions" (an array of up to 5 short, insightful study questions about '
        'these ayat that can be answered from the given tafsir). No other text.';
  }

  String _refineSystem(String lang) {
    final langName = _langNames[lang] ?? 'English';
    return 'You clean up a speech-to-text transcript of a user\'s SPOKEN question. '
        'The user is asking about the Quran and Islamic (Shia) topics, so the raw '
        'transcript often has misheard or misspelled words, wrong word boundaries, '
        'mangled proper names (surahs, prophets, imams, Islamic terms), or missing '
        'punctuation. Produce a corrected, natural version of the SAME question: fix '
        'speech-to-text errors and spelling, restore the proper names/terms clearly '
        'intended, and add punctuation. STRICT RULES: do NOT change the meaning, do '
        'NOT answer the question, do NOT add information, assumptions or extra '
        'sentences, and do NOT translate — keep it in the original language '
        '($langName). If the transcript is already correct, return it unchanged. '
        'Reply as STRICT JSON with exactly one key: "question" (the corrected '
        'question as a string). No other text.';
  }

  String _locateSystem(String lang, [int? surah]) {
    final langName = _langNames[lang] ?? 'English';
    final scope = surah != null
        ? 'Choose ONLY ayat from surah $surah (chapter $surah); ignore every other '
            'surah. If surah $surah does not address the question, return an empty array. '
        : '';
    return 'You are a Shia Quran study assistant. The input may include prior '
        'CONVERSATION followed by the latest QUESTION; use the conversation only '
        'to resolve what a follow-up refers to, then locate ayat for that latest '
        'QUESTION. Identify the Quran ayat most relevant to its SUBJECT — include '
        'ayat that '
        'mention, address, support, OR refute the matter, even when the question '
        'is framed as a claim, a comparison, or asks which sources say something '
        '(e.g. for "which sources say Solomon disbelieved", return 2:102, which '
        'states he did NOT). For a question about a prophet, person, event, or '
        'topic, return the key ayat on that subject. Use only real ayat: surah '
        '1–114 with valid ayah numbers. $scope'
        'Return the MOST relevant first, at most 6. Ayat that REJECT or contradict '
        'the claim in the question are highly relevant — include them. If no ayah '
        'is exactly on point, return the CLOSEST related ayat rather than nothing. '
        'Only return an EMPTY array when the question is genuinely unrelated to the '
        'Quran or Islam. '
        'The "note" must be written in $langName. '
        'Reply as STRICT JSON with exactly these keys: '
        '"ayat" (an array of objects each with integer "surah" and integer "ayah"); '
        '"note" (a one-sentence note on why these ayat, or why none — a string). '
        'No other text.';
  }

  /// The in-scope ATTEMPT prompt: answer strictly from the provided material, or
  /// flag (in_scope=false) that the material doesn't cover it — never reaching for
  /// outside knowledge. This both answers in-scope questions and detects scope.
  String _attemptSystem(String lang) {
    final langName = _langNames[lang] ?? 'English';
    return 'You are a careful Shia Quran study assistant. Using ONLY the provided '
        'ayah material (Arabic, translation, tafsir excerpts, Mufradat) and the '
        'prior conversation — never outside knowledge — explain what the Quran and '
        'these tafsir say in RELATION to the user\'s question. Always ground every '
        'statement in the given material and cite the specific ayat and tafsir '
        'editions you draw on. '
        'The ONLY tafsir editions available to you here are the ones in the '
        'material: al-Mizan (Allamah Tabatabai), Nemooneh (Makarem Shirazi), and '
        'Noor (Mohsen Qaraati). In THIS part cite ONLY these editions (plus the '
        'Mufradat / Raghib al-Isfahani entries and the ayat) — NEVER cite any '
        'other tafsir such as Majma\' al-Bayan, al-Tibyan, or Tafsir al-Kabir, '
        'and never claim an edition you were not given; those belong only to the '
        'broader-sources answer, not here. '
        'ALONGSIDE the tafsir you MUST ALWAYS enrich the answer with WORD-ROOT and '
        'GRAMMAR analysis (do this for every answer, not only when explicitly '
        'asked): for the key Arabic words bearing on the question and on the '
        'tafsir\'s reading, give each word\'s ROOT and literal sense from the '
        'provided Mufradat entries (cite Mufradat / Raghib al-Isfahani) and its '
        'grammatical role in the ayah — morphology and i\'rab (you MAY fully parse '
        'the PROVIDED Arabic; that is not "outside knowledge") — and use this root '
        '+ grammar to SUPPORT, VALIDATE, or qualify the tafsir\'s reading. When '
        'the user specifically asks to analyze the words, cover the ayah WORD BY '
        'WORD in order, then conclude how the grammar and roots validate the '
        'tafsir. Always list every Mufradat word/root you used in "references". '
        'If the material directly and fully answers the question, set "in_scope" '
        'true and answer clearly and thoroughly. '
        'If it does NOT directly answer it but the ayat/tafsir still bear on the '
        'subject, set "in_scope" false yet STILL explain in "answer" what they DO '
        'say about that subject (quote/point to the relevant ayat) and note what '
        'they leave unaddressed — do not go beyond the material. '
        'Only when the material is entirely unrelated to the question, set '
        '"in_scope" false with a single short sentence (in $langName) saying the '
        'provided tafsir does not address it. '
        'If an EXTERNAL DRAFT ANSWER is included, treat it as the prior reply and '
        'COMMENT on it from the Quran/tafsir — confirm what they support, qualify '
        'or correct what they do not, and add tafsir nuance — but stay grounded '
        'ONLY in the provided material and never adopt its unsupported claims. '
        'Do NOT issue any fiqh ruling or fatwa — defer to a qualified marja\'. '
        'Write entirely in $langName. '
        'Reply as STRICT JSON with exactly these keys: '
        '"answer" (a string); '
        '"in_scope" (boolean as defined above); '
        '"references" (an array listing the tafsir editions/ayat AND any Mufradat '
        'word/root entries actually used, or empty); '
        '"example" (a SHORT clarifying example when genuinely helpful, else an empty '
        'string); and '
        '"questions" (an array of up to 3 follow-up questions answerable from the '
        'same material, or empty). No other text.';
  }

  /// The OUT-OF-SCOPE prompt: the question is NOT covered by the app's tafsir, so
  /// answer from authentic Shia scholarship with NO ayah/tafsir context provided,
  /// citing precise references.
  String _beyondSystem(String lang) {
    final langName = _langNames[lang] ?? 'English';
    return 'You are a knowledgeable comparative-religion and Quran study '
        'assistant. The user\'s question is NOT covered by the app\'s provided '
        'tafsir, so answer it from the BROADEST relevant scholarship BEYOND that '
        'tafsir, and you MUST include NON-ISLAMIC and academic sources wherever '
        'they bear on the topic — not only Islamic ones. Draw on, as relevant: the '
        'Hebrew Bible / Tanakh and Talmud; the Christian Bible and tradition; '
        'other religious, historical or archaeological sources; modern academic / '
        'historical / orientalist scholarship; AND broader Islamic sources beyond '
        'the bundled tafsir (the Quran, major tafsirs such as al-Mizan and Majma\' '
        'al-Bayan, and reliable hadith collections like al-Kafi and Bihar '
        'al-Anwar). You are given NO ayah/tafsir context — work from your own '
        'knowledge. Give a COMPLETE answer that explains the reasoning and '
        'evidence; clearly ATTRIBUTE each claim to its tradition/source, and where '
        'the traditions DIFFER (e.g. how Judaism, Christianity and Islam treat a '
        'prophet, person or event) lay out each view side by side. '
        'Cite a precise reference for every claim — never just a book title. '
        'Include, when applicable: the work title and author; the volume; the '
        'chapter / book / section; the page (with edition when it matters); for '
        'scripture the exact book chapter:verse (e.g. "1 Kings 11:1–13", '
        '"Genesis 2:7", "Quran 2:102"); for a hadith the collection, bab and '
        'narration number; for academic work the author, title and year. NEVER '
        'fabricate a citation, page, verse or number; if unsure of an exact '
        'locator, give the most specific one you ARE sure of and qualify the rest '
        'rather than inventing it. '
        'Do NOT issue any fiqh ruling or fatwa — defer to a qualified marja\'. '
        'Write entirely in $langName, but keep cited work/book names in their '
        'conventional form. '
        'Reply as STRICT JSON with exactly these keys: '
        '"answer" (a string); '
        '"in_scope" (boolean — always false); '
        '"references" (a NON-EMPTY array of precise source strings as described, '
        'spanning the different traditions you actually used); '
        '"example" (a SHORT clarifying example, else an empty string); and '
        '"questions" (an array of up to 3 follow-up questions, or empty). '
        'No other text.';
  }

  String _material(List<AiAyahMaterial> ayat) {
    final b = StringBuffer();
    for (final a in ayat) {
      b.writeln('=== Ayah ${a.surah}:${a.ayah} ===');
      b.writeln('Arabic: ${a.textAr}');
      if (a.translation != null && a.translation!.trim().isNotEmpty) {
        b.writeln('Translation: ${a.translation}');
      }
      if (a.tafsir.isNotEmpty) {
        b.writeln('Tafsir:');
        for (final t in a.tafsir) {
          b.writeln('- [${t.edition} — ${t.author}] ${t.text}');
        }
      }
      if (a.mufradat.isNotEmpty) {
        b.writeln('Word meanings (Mufradat):');
        for (final m in a.mufradat) {
          final root = m.root == null ? '' : ' (root ${m.root})';
          b.writeln('- ${m.word}$root: ${m.text}');
        }
      }
      b.writeln();
    }
    return b.toString().trim();
  }

  String _answerUser({
    required List<AiAyahMaterial> ayat,
    String? summary,
    required List<String> suggestedQuestions,
    required List<AiTurn> history,
    required String question,
    String? beyondDraft,
  }) {
    final b = StringBuffer();
    b.writeln(_material(ayat));
    b.writeln();
    if (beyondDraft != null && beyondDraft.trim().isNotEmpty) {
      b.writeln('EXTERNAL DRAFT ANSWER (from broader, non-tafsir sources — '
          'COMMENT on it using ONLY the material above; confirm what the Quran/'
          'tafsir support, qualify or correct what they do not, and add relevant '
          'tafsir nuance. Do NOT adopt its claims that the material does not '
          'support):');
      b.writeln(beyondDraft.trim());
      b.writeln();
    }
    if (summary != null && summary.trim().isNotEmpty) {
      b.writeln('EARLIER SUMMARY:');
      b.writeln(summary.trim());
      b.writeln();
    }
    if (suggestedQuestions.isNotEmpty) {
      b.writeln('SUGGESTED QUESTIONS:');
      for (var i = 0; i < suggestedQuestions.length; i++) {
        b.writeln('${i + 1}. ${suggestedQuestions[i]}');
      }
      b.writeln();
    }
    if (history.isNotEmpty) {
      b.writeln('CONVERSATION SO FAR:');
      for (final h in history) {
        b.writeln('Q: ${h.question}');
        b.writeln('A: ${h.answer}');
      }
      b.writeln();
    }
    b.writeln('ANSWER THIS QUESTION (prefer the material above; if you go beyond '
        'it, set in_scope=false and cite references): $question');
    return b.toString().trim();
  }

  // ---- model-family helpers (mirrors interview_ai's OpenAiProvider) ----

  static bool _isReasoningModel(String model) {
    final m = model.toLowerCase();
    return m.startsWith('gpt-5') ||
        m.startsWith('o1') ||
        m.startsWith('o3') ||
        m.startsWith('o4');
  }

  /// gpt-5.<digit> families accept "none" (behave like a non-reasoning model);
  /// older reasoning models (gpt-5-mini, o-series) only go as low as "low".
  static String _lowestReasoningEffort(String model) {
    return RegExp(r'^gpt-5\.\d').hasMatch(model.toLowerCase()) ? 'none' : 'low';
  }

  // ---- response parsing ----

  static List<String> _stringList(dynamic v, int max) {
    if (v is! List) return const [];
    final out = v
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return out.length > max ? out.sublist(0, max) : out;
  }

  static String? _extractContent(String raw) {
    try {
      final root = jsonDecode(raw) as Map<String, dynamic>;
      final choices = root['choices'] as List?;
      if (choices == null || choices.isEmpty) return null;
      final msg = (choices.first as Map)['message'] as Map?;
      return msg?['content'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Strips to the outermost {...} (handles ```json fences / stray prose) and decodes.
  static Map<String, dynamic>? _parseJsonObject(String s) {
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      return jsonDecode(s.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static String _short(String s) => s.length <= 300 ? s : '${s.substring(0, 300)}…';
}
