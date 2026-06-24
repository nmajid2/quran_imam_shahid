import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/config.dart';
import '../ai/openai_client.dart';

/// Persisted AI settings — three role-specific models plus the out-of-tafsir mode.
class AiSettingsStore {
  static const _storage = FlutterSecureStorage();
  static const _kAnswer = 'ai_model_answer';
  static const _kOosAnswer = 'ai_model_oos_answer';
  static const _kClassify = 'ai_model_classify';
  static const _kRefine = 'ai_model_refine';
  static const _kOos = 'out_of_scope_mode';
  static const _kTtsVoice = 'tts_voice';
  static const _kTtsEnabled = 'tts_enabled';
  static const _kTtsSpeed = 'tts_speed';
  static const _kLegacy = 'ai_model'; // pre-split single model

  static Future<String> _model(String key, String fallback) async {
    final saved = await _storage.read(key: key);
    if (saved != null && AppConfig.aiModels.contains(saved)) return saved;
    return fallback;
  }

  /// The answer model migrates the old single `ai_model` value if present, so the
  /// user's previous choice carries over.
  static Future<String> loadAnswerModel() async {
    final saved = await _storage.read(key: _kAnswer);
    if (saved != null && AppConfig.aiModels.contains(saved)) return saved;
    final legacy = await _storage.read(key: _kLegacy);
    if (legacy != null && AppConfig.aiModels.contains(legacy)) return legacy;
    return AppConfig.defaultAnswerModel;
  }

  static Future<String> loadOosAnswerModel() =>
      _model(_kOosAnswer, AppConfig.defaultOosAnswerModel);
  static Future<String> loadClassifyModel() =>
      _model(_kClassify, AppConfig.defaultClassifyModel);
  static Future<String> loadRefineModel() =>
      _model(_kRefine, AppConfig.defaultRefineModel);

  static Future<String> loadOutOfScopeMode() async {
    final s = await _storage.read(key: _kOos);
    return (s != null && AppConfig.outOfScopeModes.contains(s))
        ? s
        : AppConfig.defaultOutOfScopeMode;
  }

  static Future<String> loadTtsVoice() async {
    final s = await _storage.read(key: _kTtsVoice);
    return (s != null && AppConfig.ttsVoiceIds.contains(s))
        ? s
        : AppConfig.defaultTtsVoice;
  }

  static Future<bool> loadTtsEnabled() async {
    final s = await _storage.read(key: _kTtsEnabled);
    return s == null ? AppConfig.defaultTtsEnabled : s == 'true';
  }

  static Future<double> loadTtsSpeed() async {
    final s = await _storage.read(key: _kTtsSpeed);
    final v = double.tryParse(s ?? '');
    if (v == null) return AppConfig.defaultTtsSpeed;
    return v.clamp(AppConfig.ttsSpeedMin, AppConfig.ttsSpeedMax);
  }

  static Future<void> saveAnswerModel(String v) =>
      _storage.write(key: _kAnswer, value: v);
  static Future<void> saveOosAnswerModel(String v) =>
      _storage.write(key: _kOosAnswer, value: v);
  static Future<void> saveClassifyModel(String v) =>
      _storage.write(key: _kClassify, value: v);
  static Future<void> saveRefineModel(String v) =>
      _storage.write(key: _kRefine, value: v);
  static Future<void> saveOutOfScopeMode(String v) =>
      _storage.write(key: _kOos, value: v);
  static Future<void> saveTtsVoice(String v) =>
      _storage.write(key: _kTtsVoice, value: v);
  static Future<void> saveTtsEnabled(bool v) =>
      _storage.write(key: _kTtsEnabled, value: '$v');
  static Future<void> saveTtsSpeed(double v) =>
      _storage.write(key: _kTtsSpeed, value: '$v');
}

/// Model for answering questions / summaries from the tafsir material
/// (`answer` attempt, `summarize`, `locateAyat`).
final answerModelProvider =
    StateProvider<String>((_) => AppConfig.defaultAnswerModel);

/// Model used when a question is OUT of the tafsir's scope — answered from
/// broader authentic sources with only the bare question (no ayah/tafsir).
final oosAnswerModelProvider =
    StateProvider<String>((_) => AppConfig.defaultOosAnswerModel);

/// Model for classifying a typed/spoken request into a command (`routeCommand`).
final classifyModelProvider =
    StateProvider<String>((_) => AppConfig.defaultClassifyModel);

/// Model for cleaning up a speech-to-text transcript (`refineTranscript`).
final refineModelProvider =
    StateProvider<String>((_) => AppConfig.defaultRefineModel);

/// What to do when a question is outside the provided tafsir.
final outOfScopeModeProvider =
    StateProvider<String>((_) => AppConfig.defaultOutOfScopeMode);

/// The narrator (OpenAI TTS voice) used to read answers aloud.
final ttsVoiceProvider = StateProvider<String>((_) => AppConfig.defaultTtsVoice);

/// Whether voice-asked questions get their answer read aloud.
final ttsEnabledProvider =
    StateProvider<bool>((_) => AppConfig.defaultTtsEnabled);

/// Read-aloud speed (OpenAI TTS `speed`).
final ttsSpeedProvider =
    StateProvider<double>((_) => AppConfig.defaultTtsSpeed);

/// The direct OpenAI client used for all in-app AI features.
final openAiClientProvider = Provider<OpenAiClient>((_) => OpenAiClient());
