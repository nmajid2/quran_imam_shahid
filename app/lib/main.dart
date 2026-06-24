import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'core/theme_controller.dart';
import 'features/audio/audio_prefs.dart';
import 'features/settings/ai_settings_controller.dart';
import 'features/surah_list/surah_list_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final saved = await ThemeStore.load(); // load before first frame (no flash)
  final answerModel = await AiSettingsStore.loadAnswerModel();
  final oosAnswerModel = await AiSettingsStore.loadOosAnswerModel();
  final classifyModel = await AiSettingsStore.loadClassifyModel();
  final refineModel = await AiSettingsStore.loadRefineModel();
  final oosMode = await AiSettingsStore.loadOutOfScopeMode();
  final ttsVoice = await AiSettingsStore.loadTtsVoice();
  final ttsEnabled = await AiSettingsStore.loadTtsEnabled();
  final ttsSpeed = await AiSettingsStore.loadTtsSpeed();
  final playTranslation = await AudioPrefs.loadPlayTranslation();
  runApp(
    ProviderScope(
      overrides: [
        presetIdProvider.overrideWith((ref) => saved.preset),
        themeModeProvider.overrideWith((ref) => saved.mode),
        answerModelProvider.overrideWith((ref) => answerModel),
        oosAnswerModelProvider.overrideWith((ref) => oosAnswerModel),
        classifyModelProvider.overrideWith((ref) => classifyModel),
        refineModelProvider.overrideWith((ref) => refineModel),
        outOfScopeModeProvider.overrideWith((ref) => oosMode),
        ttsVoiceProvider.overrideWith((ref) => ttsVoice),
        ttsEnabledProvider.overrideWith((ref) => ttsEnabled),
        ttsSpeedProvider.overrideWith((ref) => ttsSpeed),
        playTranslationProvider.overrideWith((ref) => playTranslation),
      ],
      child: const QuranImamShahidApp(),
    ),
  );
}

class QuranImamShahidApp extends ConsumerWidget {
  const QuranImamShahidApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preset = presetById(ref.watch(presetIdProvider));
    final mode = ref.watch(themeModeProvider);

    // Persist changes.
    ref.listen(presetIdProvider, (_, v) => ThemeStore.savePreset(v));
    ref.listen(themeModeProvider, (_, v) => ThemeStore.saveMode(v));
    ref.listen(answerModelProvider, (_, v) => AiSettingsStore.saveAnswerModel(v));
    ref.listen(
        oosAnswerModelProvider, (_, v) => AiSettingsStore.saveOosAnswerModel(v));
    ref.listen(
        classifyModelProvider, (_, v) => AiSettingsStore.saveClassifyModel(v));
    ref.listen(refineModelProvider, (_, v) => AiSettingsStore.saveRefineModel(v));
    ref.listen(
        outOfScopeModeProvider, (_, v) => AiSettingsStore.saveOutOfScopeMode(v));
    ref.listen(ttsVoiceProvider, (_, v) => AiSettingsStore.saveTtsVoice(v));
    ref.listen(ttsEnabledProvider, (_, v) => AiSettingsStore.saveTtsEnabled(v));
    ref.listen(ttsSpeedProvider, (_, v) => AiSettingsStore.saveTtsSpeed(v));
    ref.listen(
        playTranslationProvider, (_, v) => AudioPrefs.savePlayTranslation(v));

    return MaterialApp(
      title: 'Quran Imam Shahid',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(preset, Brightness.light),
      darkTheme: AppTheme.build(preset, Brightness.dark),
      themeMode: mode,
      themeAnimationCurve: Curves.easeOutCubic,
      themeAnimationDuration: const Duration(milliseconds: 450),
      supportedLocales: const [Locale('fa'), Locale('en'), Locale('nl')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SurahListPage(),
    );
  }
}
