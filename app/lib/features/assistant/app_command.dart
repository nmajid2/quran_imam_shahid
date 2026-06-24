/// The fixed allow-list of commands the AI router may produce. The app maps each
/// known intent to a typed value and executes ONLY these; an unknown/invalid
/// intent becomes [NoneCommand] and is surfaced as "not understood" — there is no
/// path that runs an arbitrary model-returned string (project hard-rule #2).

sealed class AppCommand {
  const AppCommand();
}

class OpenSurahCommand extends AppCommand {
  const OpenSurahCommand(this.surah, this.fromAyah);
  final int surah;
  final int? fromAyah;
}

class ReciteCommand extends AppCommand {
  const ReciteCommand(this.surah, this.fromAyah, this.continuous, {this.query});

  /// The surah to recite, or null for a content-based recite ("read the ayah
  /// that says …") whose ayah must first be located from [query].
  final int? surah;

  /// The ayah to start at (null = from the surah's first ayah).
  final int? fromAyah;

  /// Whether recitation keeps playing the rest of the surah after [fromAyah]
  /// (true for "recite the surah" / "from ayah X onward"), or stops after that
  /// single ayah (false for "read ayah X").
  final bool continuous;

  /// When [surah] is null, the meaning/description of the ayah to find and
  /// recite (e.g. "the ayah that says Solomon did not disbelieve").
  final String? query;
}

class SearchQuranCommand extends AppCommand {
  const SearchQuranCommand(this.query);
  final String query;
}

class SearchInSurahCommand extends AppCommand {
  const SearchInSurahCommand(this.surah, this.query);
  final int surah;
  final String query;
}

class OpenTafsirCommand extends AppCommand {
  const OpenTafsirCommand(this.surah, this.ayah);
  final int surah;
  final int ayah;
}

class AskCommand extends AppCommand {
  const AskCommand(this.question, this.scopeGuess, {this.tafsirOnly = false});
  final String question;
  final String scopeGuess; // in_tafsir | outside | unknown

  /// True when the user restricted the answer to the Quran / provided tafsir
  /// ("show the Quran ayah that …", "answer from the tafsir") — the Ask flow
  /// then skips the out-of-tafsir (broader sources) part for this question.
  final bool tafsirOnly;
}

class NoneCommand extends AppCommand {
  const NoneCommand(this.reason);
  final String reason;
}

/// A parsed command plus the router's short confirmation/`say` and confidence.
class RoutedCommand {
  const RoutedCommand(this.command, this.say, this.confidence);
  final AppCommand command;
  final String say;
  final String confidence; // high | low

  /// Parse router JSON into a typed command. Anything malformed or unknown maps
  /// to [NoneCommand]; range validation (surah/ayah) is the dispatcher's job.
  factory RoutedCommand.fromJson(Map<String, dynamic> j) {
    final say = (j['say'] as String?)?.trim() ?? '';
    final confidence = (j['confidence'] as String?)?.trim() ?? 'low';
    final intent = (j['intent'] as String?)?.trim();
    final surah = _asInt(j['surah']);
    final fromAyah = _asInt(j['from_ayah']);
    final ayah = _asInt(j['ayah']);
    final query = (j['query'] as String?)?.trim();
    final question = (j['question'] as String?)?.trim();
    final scope = (j['scope_guess'] as String?)?.trim() ?? 'unknown';
    final tafsirOnly = j['tafsir_only'] == true ||
        j['tafsir_only']?.toString().toLowerCase().trim() == 'true';

    AppCommand cmd;
    switch (intent) {
      case 'open_surah' when surah != null:
        cmd = OpenSurahCommand(surah, fromAyah);
      case 'recite' when surah != null:
        // A bare "ayah" (no "from_ayah") means recite that ONE ayah and stop;
        // "from_ayah" (or neither) means recite the surah from there onward.
        final single = ayah != null && fromAyah == null;
        cmd = ReciteCommand(surah, single ? ayah : fromAyah, !single);
      case 'recite'
          when (query != null && query.isNotEmpty) ||
              (question != null && question.isNotEmpty):
        // Content-based recite ("read the ayah that says …") — no surah/number
        // given; the ayah is located by meaning, then recited.
        cmd = ReciteCommand(null, null, false,
            query: (query != null && query.isNotEmpty) ? query : question);
      case 'search_quran' when (query != null && query.isNotEmpty):
        cmd = SearchQuranCommand(query);
      case 'search_in_surah'
          when (surah != null && query != null && query.isNotEmpty):
        cmd = SearchInSurahCommand(surah, query);
      case 'open_tafsir' when (surah != null && ayah != null):
        cmd = OpenTafsirCommand(surah, ayah);
      case 'ask' when (question != null && question.isNotEmpty):
        cmd = AskCommand(question, scope, tafsirOnly: tafsirOnly);
      default:
        cmd = NoneCommand(intent == null ? 'not understood' : 'incomplete: $intent');
    }
    return RoutedCommand(cmd, say, confidence);
  }

  static int? _asInt(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));
}
