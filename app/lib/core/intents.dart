/// Client-side mirror of the gateway's intent allow-list.
///
/// SECURITY: the app maps each known action to a typed handler. An unknown action
/// is dropped (and logged) — never executed. There is no code path that runs an
/// arbitrary string as a command. This is the client half of the same boundary the
/// gateway enforces server-side.

sealed class AppIntent {
  const AppIntent();

  /// Parse a single intent from gateway JSON. Returns null for unknown actions,
  /// which callers MUST drop rather than execute.
  static AppIntent? fromJson(Map<String, dynamic> j) {
    switch (j['action']) {
      case 'speak':
        return SpeakIntent(lang: j['lang'], text: j['text']);
      case 'open_ayah':
        return OpenAyahIntent(surah: j['surah'], ayah: j['ayah']);
      case 'play_recitation':
        return PlayRecitationIntent(
          surah: j['surah'],
          from: j['from'],
          to: j['to'],
          repeat: (j['repeat'] ?? 1) as int,
        );
      case 'answer':
        return AnswerIntent(
          text: j['text'],
          confidence: j['confidence'] ?? 'partial',
          sources: (j['sources'] as List?)?.cast<Map<String, dynamic>>() ?? const [],
        );
      case 'show_tafsir':
        return ShowTafsirIntent(
          surah: j['surah'],
          ayah: j['ayah'],
          text: j['text'],
          sources: (j['sources'] as List?)?.cast<Map<String, dynamic>>() ?? const [],
        );
      case 'set_bookmark':
        return SetBookmarkIntent(surah: j['surah'], ayah: j['ayah']);
      case 'none':
        return NoneIntent(reason: j['reason'] ?? '');
      default:
        return null; // unknown -> dropped by the caller
    }
  }
}

class SpeakIntent extends AppIntent {
  const SpeakIntent({required this.lang, required this.text});
  final String lang;
  final String text;
}

class OpenAyahIntent extends AppIntent {
  const OpenAyahIntent({required this.surah, required this.ayah});
  final int surah;
  final int ayah;
}

class PlayRecitationIntent extends AppIntent {
  const PlayRecitationIntent({
    required this.surah,
    required this.from,
    required this.to,
    this.repeat = 1,
  });
  final int surah;
  final int from;
  final int to;
  final int repeat;
}

class AnswerIntent extends AppIntent {
  const AnswerIntent({
    required this.text,
    required this.confidence,
    required this.sources,
  });
  final String text;
  final String confidence;
  final List<Map<String, dynamic>> sources;
}

class ShowTafsirIntent extends AppIntent {
  const ShowTafsirIntent({
    required this.surah,
    required this.ayah,
    required this.text,
    required this.sources,
  });
  final int surah;
  final int ayah;
  final String text;
  final List<Map<String, dynamic>> sources;
}

class SetBookmarkIntent extends AppIntent {
  const SetBookmarkIntent({required this.surah, required this.ayah});
  final int surah;
  final int ayah;
}

class NoneIntent extends AppIntent {
  const NoneIntent({required this.reason});
  final String reason;
}
