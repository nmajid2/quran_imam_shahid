import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/config.dart';
import '../ai/openai_client.dart';

/// Persisted AI settings — currently just the chosen OpenAI model.
class AiSettingsStore {
  static const _storage = FlutterSecureStorage();
  static const _kModel = 'ai_model';

  /// The saved model, falling back to the default (and ignoring a stale value no
  /// longer in the selectable list).
  static Future<String> loadModel() async {
    final saved = await _storage.read(key: _kModel);
    if (saved != null && AppConfig.aiModels.contains(saved)) return saved;
    return AppConfig.defaultAiModel;
  }

  static Future<void> saveModel(String id) =>
      _storage.write(key: _kModel, value: id);
}

/// Selected OpenAI model id. Seeded from storage via an override in main().
final aiModelProvider = StateProvider<String>((_) => AppConfig.defaultAiModel);

/// The direct OpenAI client used for the in-app AI tafsir summary.
final openAiClientProvider = Provider<OpenAiClient>((_) => OpenAiClient());
