import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';

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
/// questions answerable from the same material.
class AiAnswer {
  final String answer;
  final String? example;
  final List<String> questions;
  const AiAnswer(this.answer, this.example, this.questions);
}

/// One prior Q&A turn, re-sent to the stateless model as context.
typedef AiTurn = ({String question, String answer});

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
  }) async {
    final data = await _chatJson(model, _summarySystem(lang), _material(ayat));
    final summary = (data['summary'] as String?)?.trim() ?? '';
    final points = _stringList(data['key_points'], 6);
    final questions = _stringList(data['questions'], 5);
    if (summary.isEmpty && points.isEmpty) {
      throw AiException('The AI response was empty.');
    }
    return AiSummary(summary, points, questions);
  }

  /// Round 2: answer one selected question. Stateless — re-sends [ayat], the
  /// [suggestedQuestions], the prior [history], and the [question].
  Future<AiAnswer> answer({
    required String model,
    required String lang,
    required List<AiAyahMaterial> ayat,
    required String question,
    String? summary,
    List<String> suggestedQuestions = const [],
    List<AiTurn> history = const [],
  }) async {
    final user = _answerUser(
      ayat: ayat,
      summary: summary,
      suggestedQuestions: suggestedQuestions,
      history: history,
      question: question,
    );
    final data = await _chatJson(model, _answerSystem(lang), user);
    final ans = (data['answer'] as String?)?.trim() ?? '';
    final exampleRaw = (data['example'] as String?)?.trim();
    final example =
        (exampleRaw == null || exampleRaw.isEmpty) ? null : exampleRaw;
    final followUps = _stringList(data['questions'], 3);
    if (ans.isEmpty) throw AiException('The AI gave no answer.');
    return AiAnswer(ans, example, followUps);
  }

  // ---- request ----

  Future<Map<String, dynamic>> _chatJson(
      String model, String system, String user) async {
    if (_apiKey.trim().isEmpty) {
      throw AiException(
          'OpenAI key not configured. Rebuild with --dart-define=OPENAI_API_KEY=sk-…');
    }
    final body = <String, dynamic>{
      'model': model,
      'max_completion_tokens': 1200,
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

    http.Response resp;
    try {
      resp = await _http.post(
        _endpoint,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } catch (e) {
      throw AiException('Could not reach OpenAI: $e');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AiException('OpenAI error ${resp.statusCode}: ${_short(resp.body)}');
    }
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
        'general reader can understand. Do NOT invent tafsir or hadith beyond what '
        'is given. Do NOT issue any fiqh ruling or fatwa — defer those to a '
        'qualified marja\'. Write entirely in $langName. '
        'Reply as STRICT JSON with exactly these keys: '
        '"summary" (a string, 2–4 short paragraphs), '
        '"key_points" (an array of 3–6 short strings), and '
        '"questions" (an array of up to 5 short, insightful study questions about '
        'these ayat that can be answered from the given tafsir). No other text.';
  }

  String _answerSystem(String lang) {
    final langName = _langNames[lang] ?? 'English';
    return 'You are a careful Shia Quran study assistant. Using ONLY the provided '
        'ayah material (Arabic, translation, tafsir excerpts, Mufradat) and the '
        'prior conversation, answer the user\'s selected question clearly and '
        'concisely. Do NOT invent content beyond the material; if it does not cover '
        'the question, say so briefly. Do NOT issue any fiqh ruling or fatwa — defer '
        'to a qualified marja\'. Write entirely in $langName. '
        'Reply as STRICT JSON with exactly these keys: '
        '"answer" (a string); '
        '"example" (a SHORT, concrete example that clarifies the concept — include '
        'one ONLY when the concept is genuinely confusing and an example truly aids '
        'understanding; otherwise an empty string); and '
        '"questions" (an array of up to 3 NEW follow-up questions answerable from '
        'the same material, or an empty array if none are natural). No other text.';
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
  }) {
    final b = StringBuffer();
    b.writeln(_material(ayat));
    b.writeln();
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
    b.writeln('ANSWER THIS QUESTION (only from the material above): $question');
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
