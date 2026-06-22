import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'core/theme_controller.dart';
import 'features/settings/ai_settings_controller.dart';
import 'features/surah_list/surah_list_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final saved = await ThemeStore.load(); // load before first frame (no flash)
  final aiModel = await AiSettingsStore.loadModel();
  runApp(
    ProviderScope(
      overrides: [
        presetIdProvider.overrideWith((ref) => saved.preset),
        themeModeProvider.overrideWith((ref) => saved.mode),
        aiModelProvider.overrideWith((ref) => aiModel),
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
    ref.listen(aiModelProvider, (_, v) => AiSettingsStore.saveModel(v));

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
