import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/surah_list/surah_list_page.dart';

void main() {
  runApp(const ProviderScope(child: QuranImamShahidApp()));
}

class QuranImamShahidApp extends StatelessWidget {
  const QuranImamShahidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quran Imam Shahid',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // fa (RTL), en, nl — see TECHNICAL_DESIGN §9.
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
