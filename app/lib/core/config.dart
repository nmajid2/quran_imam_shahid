/// App configuration. The app is fully standalone: Quran text, search, reciters
/// and audio URLs are bundled/served on-device; only the AI features call out
/// (directly to OpenAI). No gateway.
class AppConfig {
  /// Supported UI / content languages.
  static const List<String> languages = ['fa', 'en', 'nl'];
  static const String defaultLanguage = 'fa';

  /// OpenAI key for the in-app AI tafsir summary. The app calls OpenAI directly
  /// (no gateway) for this feature, so the key is baked in at build time:
  ///   flutter run --dart-define=OPENAI_API_KEY=sk-...
  /// Empty → the AI summary button explains it needs to be configured.
  static const String openAiApiKey =
      String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');

  /// Selectable OpenAI models for the AI features (first is the default).
  static const List<String> aiModels = [
    'gpt-4o-mini',
    'gpt-5.4-mini',
    'gpt-5-mini',
    'gpt-4o',
    'gpt-5.1',
  ];
  static const String defaultAiModel = 'gpt-4o-mini';

  /// Per-role model defaults. The "answer" role does the heavy lifting (replies /
  /// summaries); classify (command routing) and refine (voice cleanup) are light.
  static const String defaultAnswerModel = 'gpt-4o-mini';
  static const String defaultOosAnswerModel = 'gpt-4o-mini';
  static const String defaultClassifyModel = 'gpt-4o-mini';
  static const String defaultRefineModel = 'gpt-4o-mini';

  // ---- Text-to-speech (read AI answers aloud for voice-asked questions) ----

  /// OpenAI TTS model. gpt-4o-mini-tts is the current multilingual TTS model and
  /// supports the full voice set below.
  static const String ttsModel = 'gpt-4o-mini-tts';

  /// Selectable narrators (OpenAI TTS voices). [id] is the API value; the label
  /// + descriptor are shown in settings.
  static const List<({String id, String label, String blurb})> ttsVoices = [
    (id: 'alloy', label: 'Alloy', blurb: 'Neutral, balanced'),
    (id: 'ash', label: 'Ash', blurb: 'Clear, confident'),
    (id: 'ballad', label: 'Ballad', blurb: 'Warm, gentle'),
    (id: 'coral', label: 'Coral', blurb: 'Bright, friendly'),
    (id: 'echo', label: 'Echo', blurb: 'Calm, measured'),
    (id: 'fable', label: 'Fable', blurb: 'Expressive, storytelling'),
    (id: 'nova', label: 'Nova', blurb: 'Bright, energetic'),
    (id: 'onyx', label: 'Onyx', blurb: 'Deep, authoritative'),
    (id: 'sage', label: 'Sage', blurb: 'Soft, thoughtful'),
    (id: 'shimmer', label: 'Shimmer', blurb: 'Light, soothing'),
    (id: 'verse', label: 'Verse', blurb: 'Natural, narrative'),
  ];
  static const List<String> ttsVoiceIds = [
    'alloy', 'ash', 'ballad', 'coral', 'echo', 'fable', 'nova', 'onyx', 'sage',
    'shimmer', 'verse'
  ];
  static const String defaultTtsVoice = 'alloy';
  static const bool defaultTtsEnabled = true;

  /// Reading speed (OpenAI TTS `speed`, 0.25–4.0; 1.0 = normal).
  static const double defaultTtsSpeed = 1.0;
  static const double ttsSpeedMin = 0.5;
  static const double ttsSpeedMax = 2.0;

  /// OpenAI TTS voices are multilingual and follow the input text. They are
  /// strong for English & Dutch; Persian (Farsi) is experimental (may be
  /// accented). Shown under the voice picker.
  static const String ttsLangNote =
      'Voices are multilingual — strong for English & Dutch; Persian is '
      'experimental and may sound accented.';

  /// Max characters sent to TTS in one request (OpenAI limit is ~4096).
  static const int ttsMaxChars = 4000;

  /// How to handle a question the provided tafsir doesn't cover.
  static const String oosTafsirOnly = 'tafsir_only';
  static const String oosWithSources = 'with_sources';
  static const String oosAskFirst = 'ask_first';
  static const List<String> outOfScopeModes = [
    oosWithSources,
    oosTafsirOnly,
    oosAskFirst,
  ];
  static const String defaultOutOfScopeMode = oosWithSources;
}
