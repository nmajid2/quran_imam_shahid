import 'ai_usage.dart';
import 'openai_client.dart';

/// One question→answer exchange inside an [AskSession]. A turn can have TWO
/// parts: the Quran+tafsir-grounded answer ([answer]/[references]/[refs], with
/// [inScope] telling whether the tafsir actually covered it), and an optional
/// out-of-tafsir answer from broader sources ([beyondAnswer]/[beyondReferences]).
class AskTurn {
  AskTurn({
    required this.question,
    required this.answer,
    this.example,
    this.inScope = true,
    this.references = const [],
    this.refs = const [],
    this.beyondAnswer,
    this.beyondExample,
    this.beyondReferences = const [],
    this.usage = const [],
    this.extraCosts = const [],
  });

  final String question;
  final String answer; // part 1: from the Quran + provided tafsir
  final String? example;
  final bool inScope; // whether the provided tafsir covered the question
  final List<String> references; // part-1 sources (tafsir editions / ayat)
  final List<AiAyahRef> refs; // ayat the AI located for this question

  final String? beyondAnswer; // part 2: from broader sources (null = not run)
  final String? beyondExample;
  final List<String> beyondReferences; // part-2 external citations

  final List<AiCallUsage> usage; // token usage per model call for this turn
  final List<AiExtraCost> extraCosts; // non-token costs (STT, TTS) for this turn

  /// Both parts joined, for re-sending as conversation history to the model.
  String get fullAnswer =>
      beyondAnswer == null ? answer : '$answer\n\n$beyondAnswer';

  Map<String, dynamic> toJson() => {
        'question': question,
        'answer': answer,
        'example': example,
        'in_scope': inScope,
        'references': references,
        'refs': [
          for (final r in refs) {'surah': r.surah, 'ayah': r.ayah}
        ],
        'beyond_answer': beyondAnswer,
        'beyond_example': beyondExample,
        'beyond_references': beyondReferences,
        'usage': [for (final u in usage) u.toJson()],
        'extra_costs': [for (final c in extraCosts) c.toJson()],
      };

  factory AskTurn.fromJson(Map<String, dynamic> j) => AskTurn(
        question: (j['question'] ?? '') as String,
        answer: (j['answer'] ?? '') as String,
        example: j['example'] as String?,
        inScope: (j['in_scope'] ?? true) as bool,
        references: ((j['references'] ?? const []) as List)
            .map((e) => e.toString())
            .toList(),
        refs: ((j['refs'] ?? const []) as List)
            .map((e) => (
                  surah: (e['surah'] as num).toInt(),
                  ayah: (e['ayah'] as num).toInt(),
                ))
            .toList(),
        beyondAnswer: j['beyond_answer'] as String?,
        beyondExample: j['beyond_example'] as String?,
        beyondReferences: ((j['beyond_references'] ?? const []) as List)
            .map((e) => e.toString())
            .toList(),
        usage: ((j['usage'] ?? const []) as List)
            .map((e) => AiCallUsage.fromJson(e as Map<String, dynamic>))
            .toList(),
        extraCosts: ((j['extra_costs'] ?? const []) as List)
            .map((e) => AiExtraCost.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A saved "Ask the Quran" conversation. Capped at [maxQuestions] exchanges;
/// once full, the user starts a new session.
class AskSession {
  AskSession({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    List<AskTurn>? turns,
    this.surah,
    this.ayah,
    this.ayahEnd,
  }) : turns = turns ?? [];

  static const int maxQuestions = 5;

  final String id;
  final int createdAt; // epoch ms
  int updatedAt;
  final List<AskTurn> turns;

  /// Where this conversation came from, for the history label. All null = the
  /// whole-Quran "Ask the Quran". [surah] only = "Ask about this surah".
  /// [surah]+[ayah] (+[ayahEnd]) = a per-ayah AI summary conversation.
  final int? surah;
  final int? ayah;
  final int? ayahEnd;

  bool get isEmpty => turns.isEmpty;
  bool get isFull => turns.length >= maxQuestions;

  /// A short title for the session list — the first question asked.
  String get title => turns.isEmpty ? 'New conversation' : turns.first.question;

  /// Short badge describing the conversation's scope (empty for whole-Quran).
  String get scopeLabel {
    if (surah == null) return '';
    if (ayah == null) return 'Surah $surah';
    if (ayahEnd != null && ayahEnd != ayah) return '$surah:$ayah–$ayahEnd';
    return '$surah:$ayah';
  }

  /// Prior exchanges as model history for [OpenAiClient.answer]. Uses the full
  /// (tafsir + beyond) answer so follow-ups see everything that was said.
  List<AiTurn> get history =>
      [for (final t in turns) (question: t.question, answer: t.fullAnswer)];

  /// Union of every ayah the session has touched, most-recent first — used to
  /// keep follow-ups grounded even when a follow-up locates no new ayat.
  List<AiAyahRef> get cumulativeRefs {
    final seen = <String>{};
    final out = <AiAyahRef>[];
    for (final t in turns.reversed) {
      for (final r in t.refs) {
        final k = '${r.surah}:${r.ayah}';
        if (seen.add(k)) out.add(r);
      }
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'surah': surah,
        'ayah': ayah,
        'ayah_end': ayahEnd,
        'turns': [for (final t in turns) t.toJson()],
      };

  factory AskSession.fromJson(Map<String, dynamic> j) => AskSession(
        id: j['id'] as String,
        createdAt: (j['created_at'] as num).toInt(),
        updatedAt: (j['updated_at'] as num).toInt(),
        surah: (j['surah'] as num?)?.toInt(),
        ayah: (j['ayah'] as num?)?.toInt(),
        ayahEnd: (j['ayah_end'] as num?)?.toInt(),
        turns: ((j['turns'] ?? const []) as List)
            .map((e) => AskTurn.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
