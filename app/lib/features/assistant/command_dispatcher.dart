import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../ai/ask_quran_sheet.dart';
import '../ai/ask_sessions_controller.dart';
import '../reader/surah_reader_page.dart';
import '../search/quran_search_page.dart';
import '../settings/ai_settings_controller.dart';
import 'app_command.dart';

/// Validates a routed command against the bundled Quran (surah 1–114, ayah in
/// range) and executes it via Navigator / providers. Inline whole-Quran search is
/// handed back to the caller (the home shows it in-place) via [onInlineSearch].
class CommandDispatcher {
  const CommandDispatcher(this.context, this.ref);
  final BuildContext context;
  final WidgetRef ref;

  Future<void> run(RoutedCommand routed,
      {required void Function(String query) onInlineSearch,
      bool fromVoice = false}) async {
    final store = ref.read(localContentProvider);
    await store.ensureLoaded();
    final cmd = routed.command;

    int? validAyah(int surah, int? ayah) {
      if (ayah == null) return null;
      final count = store.getSurah(surah).ayat.length;
      return (ayah >= 1 && ayah <= count) ? ayah : null;
    }

    bool validSurah(int s) => s >= 1 && s <= 114;

    switch (cmd) {
      case OpenSurahCommand(:final surah, :final fromAyah):
        if (!validSurah(surah)) return _toast('I couldn\'t find that surah.');
        _say(routed);
        _push(SurahReaderPage(
            number: surah, initialAyah: validAyah(surah, fromAyah)));

      case ReciteCommand(
          :final surah,
          :final fromAyah,
          :final continuous,
          :final query
        ):
        if (surah == null) {
          // Content-based recite: locate the ayah by meaning, then recite it.
          if (query == null || query.isEmpty) {
            return _toast('I couldn\'t find that ayah.');
          }
          final located = await ref.read(openAiClientProvider).locateAyat(
                model: ref.read(answerModelProvider),
                lang: ref.read(languageProvider),
                question: query,
              );
          final hit = located.ayat.isNotEmpty ? located.ayat.first : null;
          if (hit == null || !validSurah(hit.surah)) {
            return _toast('I couldn\'t find that ayah.');
          }
          final a = validAyah(hit.surah, hit.ayah) ?? 1;
          _say(routed);
          return _push(SurahReaderPage(
              number: hit.surah,
              initialAyah: a,
              autoplayFrom: a,
              autoplayContinuous: false));
        }
        if (!validSurah(surah)) return _toast('I couldn\'t find that surah.');
        final from = validAyah(surah, fromAyah) ?? 1;
        _say(routed);
        _push(SurahReaderPage(
            number: surah,
            initialAyah: from,
            autoplayFrom: from,
            autoplayContinuous: continuous));

      case OpenTafsirCommand(:final surah, :final ayah):
        if (!validSurah(surah)) return _toast('I couldn\'t find that surah.');
        final a = validAyah(surah, ayah);
        if (a == null) return _toast('That ayah is out of range.');
        _say(routed);
        _push(SurahReaderPage(
            number: surah, initialAyah: a, autoOpenTafsir: true));

      case SearchInSurahCommand(:final surah, :final query):
        if (!validSurah(surah)) return _toast('I couldn\'t find that surah.');
        _say(routed);
        _push(QuranSearchPage(surah: surah, initialQuery: query));

      case SearchQuranCommand(:final query):
        onInlineSearch(query); // home renders results in-place

      case AskCommand(:final question, :final tafsirOnly):
        // Scope (in/out of tafsir) is decided inside the sheet after it locates
        // the ayat and tries the tafsir — including the ask-first confirm.
        // [tafsirOnly] restricts this question to the Quran/tafsir part.
        final session = ref.read(askSessionsProvider.notifier).newSession();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => AskQuranSheet(
            session: session,
            lang: ref.read(languageProvider),
            initialQuestion: question,
            initialTafsirOnly: tafsirOnly,
            initialFromVoice: fromVoice,
          ),
        );

      case NoneCommand():
        _toast(routed.say.isNotEmpty
            ? routed.say
            : 'Sorry, I didn\'t understand that — try rephrasing.');
    }
  }

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _say(RoutedCommand r) {
    if (r.say.isNotEmpty) _toast(r.say);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}
