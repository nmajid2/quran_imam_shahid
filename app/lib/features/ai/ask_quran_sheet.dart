import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../assistant/app_command.dart';
import '../assistant/command_dispatcher.dart';
import '../audio/audio_controller.dart';
import '../reader/ai_summary.dart';
import '../reader/surah_reader_page.dart';
import '../search/quran_search_page.dart';
import '../settings/ai_settings_controller.dart';
import 'ai_cost_pending.dart';
import 'ai_input_bar.dart';
import 'ai_usage.dart';
import 'ai_usage_footer.dart';
import 'ask_session.dart';
import 'ask_sessions_controller.dart';
import 'openai_client.dart';
import 'part_audio_player.dart';
import 'tts_controller.dart';

/// Home "ask the Quran" conversation. Each question runs:
///   1. the AI locates the ayat most relevant to it;
///   2. the app gathers those ayat's authentic tafsir + Mufradat (offline);
///   3. the AI composes a grounded answer (out-of-scope parts flagged + cited).
/// Follow-ups reuse the session's prior exchanges + accumulated ayat, up to
/// [AskSession.maxQuestions]. Completed turns are persisted via
/// [AskSessionsController] so the session can be reopened later.
class AskQuranSheet extends ConsumerStatefulWidget {
  const AskQuranSheet({
    super.key,
    required this.session,
    required this.lang,
    this.surah,
    this.persist = true,
    this.initialQuestion,
    this.initialTafsirOnly = false,
    this.initialFromVoice = false,
  });
  final AskSession session;
  final String lang;

  /// When true, [initialQuestion] came from voice, so its answer is read aloud.
  final bool initialFromVoice;

  /// When set (opened from a voice/text "ask …" command), this question is
  /// submitted automatically as the conversation opens.
  final String? initialQuestion;

  /// When true, [initialQuestion] was restricted to the Quran/tafsir by the
  /// user ("show the Quran ayah that …"), so its out-of-tafsir part is skipped.
  final bool initialTafsirOnly;

  /// When set, the question is answered only from this surah (the reader's
  /// "ask about this surah" flow); the located ayat are restricted to it.
  final int? surah;

  /// Whether completed turns are saved to the home session history. Surah-scoped
  /// conversations are ephemeral (persist = false).
  final bool persist;

  @override
  ConsumerState<AskQuranSheet> createState() => _AskQuranSheetState();
}

enum _Phase { idle, locating, gathering, answering, error }

class _AskQuranSheetState extends ConsumerState<AskQuranSheet> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  // Captured in initState so it can be used safely from dispose() — ref.read is
  // not allowed once the element is being disposed.
  late final TtsController _tts;

  _Phase _phase = _Phase.idle;
  String _pendingQuestion = '';
  List<AiAyahRef> _pendingRefs = [];
  String _note = '';
  Object? _error;

  /// The out-of-tafsir answer once it returns, shown immediately while the
  /// Quran/tafsir part is still being composed (progressive display).
  AiAnswer? _pendingBeyond;

  /// The auto-submitted [widget.initialQuestion] was already classified as a
  /// question by the home router, so the first run skips command detection.
  bool _skipCommandOnce = false;

  /// Set from the router when a follow-up question restricts itself to the
  /// Quran/tafsir — skips the out-of-tafsir part for that turn.
  bool _askTafsirOnly = false;

  /// True once a "recite …" follow-up started background playback from this
  /// sheet — shows an inline now-playing/stop control so the user can control it
  /// without a reader's PlayerBar underneath.
  bool _recited = false;

  AskSession get _session => widget.session;
  bool get _isRtl => widget.lang == 'fa';
  bool get _busy =>
      _phase == _Phase.locating ||
      _phase == _Phase.gathering ||
      _phase == _Phase.answering;
  bool get _full => _session.isFull;

  @override
  void initState() {
    super.initState();
    _tts = ref.read(ttsControllerProvider.notifier);
    final q = widget.initialQuestion?.trim();
    if (q != null && q.isNotEmpty) {
      _input.text = q;
      _skipCommandOnce = true;
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _run(fromVoice: widget.initialFromVoice));
    }
  }

  @override
  void dispose() {
    // Stop any read-aloud when the conversation closes (use the captured
    // controller — ref.read is illegal during dispose).
    _tts.stop();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _run({bool fromVoice = false}) async {
    final q = _input.text.trim();
    if (q.isEmpty || _busy || _full) return;
    // Comment 2: clear the box immediately so it's ready for the next question.
    _input.clear();
    _focus.unfocus();
    final skipCommand = _skipCommandOnce;
    _skipCommandOnce = false;
    _askTafsirOnly = false;
    // Token usage across every model call this question makes.
    final usage = <AiCallUsage>[];
    setState(() {
      _pendingQuestion = q;
      _pendingRefs = [];
      _pendingBeyond = null;
      _phase = _Phase.locating;
      _error = null;
      _note = '';
    });

    // Issue 1: a follow-up may actually be a command ("recite ayah 5", "open
    // al-Baqarah", "search for patience"). Detect and run it — keeping the
    // conversation open — instead of answering it as a question. Routing also
    // captures whether the follow-up restricts itself to the Quran/tafsir.
    if (!skipCommand) {
      try {
        if (await _maybeRunCommand(q, usage)) {
          if (!mounted) return;
          // A command (recite/open/search) produces no answer turn, so any
          // pre-metered costs for this input (voice STT/refine) have nowhere to
          // land — drop them rather than carry them onto the next question.
          ref.read(pendingAiCostProvider.notifier).clear();
          setState(() {
            _phase = _Phase.idle;
            _pendingQuestion = '';
            _pendingRefs = [];
          });
          return;
        }
      } catch (_) {
        // Routing failed → fall through and treat it as a normal question.
      }
      if (!mounted) return;
    }

    // Whether THIS question is restricted to the Quran/tafsir (skips Part 2),
    // and whether we read the answer aloud (asked by voice + read-aloud on).
    final tafsirOnly = skipCommand ? widget.initialTafsirOnly : _askTafsirOnly;
    final readAloud = fromVoice && ref.read(ttsEnabledProvider);

    // Fold in costs metered before this answer existed — the home router call
    // and any voice transcription/refine from the input bar — so this response's
    // total covers everything spent producing it, not just the calls below.
    final extraCosts = <AiExtraCost>[];
    {
      final pending = ref.read(pendingAiCostProvider.notifier).drain();
      usage.addAll(pending.chat);
      extraCosts.addAll(pending.extra);
    }

    try {
      final client = ref.read(openAiClientProvider);
      final answerModel = ref.read(answerModelProvider);
      final hist = _session.history;

      // 1) Locate relevant ayat for this question (optionally scoped to a surah).
      //    Pass prior turns so a follow-up's references are resolved in context.
      final located = await client.locateAyat(
          model: answerModel,
          lang: widget.lang,
          question: q,
          surah: widget.surah,
          history: hist,
          usage: usage);
      if (!mounted) return;

      // Merge newly-located ayat with the session's accumulated ones (so a
      // follow-up like "explain more" stays grounded). Cap to bound the prompt.
      final merged = <AiAyahRef>[];
      final seen = <String>{};
      for (final r in [...located.ayat, ..._session.cumulativeRefs]) {
        if (seen.add('${r.surah}:${r.ayah}')) merged.add(r);
        if (merged.length >= 10) break;
      }
      setState(() {
        if (located.ayat.isNotEmpty) _pendingRefs = located.ayat;
        _phase = _Phase.answering;
      });

      // Out-of-tafsir part FIRST — broader sources answer the bare question. The
      // tafsir part below then comments on it. Skipped when the question is
      // restricted to the Quran/tafsir, or per the out-of-tafsir mode. (Same
      // number of model calls — just reordered so the tafsir can comment.)
      final beyond = tafsirOnly ? null : await _maybeBeyond(q, hist, usage);
      if (!mounted) return;
      // Progressive display: surface the out-of-tafsir answer now so the user
      // can start reading while the Quran/tafsir analysis is still composing.
      if (beyond != null) setState(() => _pendingBeyond = beyond);
      // Start reading the out-of-tafsir part aloud NOW — its audio plays while
      // the tafsir part is still being generated below (the tafsir audio is
      // queued after it).
      if (readAloud && beyond != null) {
        final t = plainForSpeech(beyond.answer);
        if (t.isNotEmpty) {
          ref.read(ttsControllerProvider.notifier).play(ttsIdFor(t), t);
        }
      }

      // Tafsir part — the Quran + provided-tafsir grounded answer (or a note when
      // no ayat/tafsir cover it); when [beyond] exists it COMMENTS on that answer.
      AiAnswer grounded;
      List<AiAyahRef> shownRefs;
      if (merged.isEmpty) {
        grounded = AiAnswer(
            located.note.isNotEmpty ? located.note : _noRelatedAyat,
            null,
            const [],
            inScope: false,
            references: const []);
        shownRefs = const [];
      } else {
        setState(() {
          _pendingRefs = located.ayat;
          _phase = _Phase.gathering;
        });
        final material = await _gather(merged);
        if (!mounted) return;
        if (material.isEmpty) {
          throw AiException('No tafsir or word data found for the related ayat.');
        }
        setState(() => _phase = _Phase.answering);
        grounded = await client.answer(
          model: answerModel,
          lang: widget.lang,
          ayat: material,
          question: q,
          history: hist,
          beyondDraft: beyond?.answer,
          usage: usage,
        );
        shownRefs = located.ayat;
      }
      if (!mounted) return;

      // When read aloud (voice questions), estimate the TTS cost of the parts we
      // play so it shows in this response's total too. Mirrors the play/enqueue
      // below: the out-of-tafsir part, then the tafsir part.
      if (readAloud) {
        for (final txt in [beyond?.answer, grounded.answer]) {
          if (txt == null) continue;
          final p = plainForSpeech(txt);
          if (p.isEmpty) continue;
          extraCosts.add(AiExtraCost(
              kind: 'tts', costUsd: estimateTtsCost(p).costUsd, estimated: true));
        }
      }

      final turn = AskTurn(
        question: q,
        answer: grounded.answer,
        example: grounded.example,
        inScope: grounded.inScope,
        references: grounded.references,
        refs: shownRefs,
        beyondAnswer: beyond?.answer,
        beyondExample: beyond?.example,
        beyondReferences: beyond?.references ?? const [],
        usage: usage,
        extraCosts: extraCosts,
      );
      if (widget.persist) {
        ref.read(askSessionsProvider.notifier).addTurn(_session, turn);
      } else {
        _session.turns.add(turn);
        _session.updatedAt = DateTime.now().millisecondsSinceEpoch;
      }
      setState(() {
        _phase = _Phase.idle;
        _pendingQuestion = '';
        _pendingRefs = [];
        _pendingBeyond = null;
      });
      // Read the tafsir part aloud: queued after the out-of-tafsir audio when
      // both parts exist, or on its own when there's no out-of-tafsir part.
      if (readAloud) {
        final t = plainForSpeech(grounded.answer);
        if (t.isNotEmpty) {
          final tts = ref.read(ttsControllerProvider.notifier);
          beyond != null ? tts.enqueue(ttsIdFor(t), t) : tts.play(ttsIdFor(t), t);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _phase = _Phase.error;
      });
    }
  }

  /// Classify [q] against the command allow-list. Recite plays in the
  /// background so the conversation stays open; navigation/search commands push
  /// their page (the sheet remains underneath, so the user returns here after).
  /// Returns true when [q] was an executable command; false for a real question.
  Future<bool> _maybeRunCommand(String q, List<AiCallUsage> usage) async {
    final client = ref.read(openAiClientProvider);
    var json = await client.routeCommand(
        model: ref.read(classifyModelProvider),
        lang: widget.lang,
        text: q,
        usage: usage);
    if (!mounted) return false;
    // In a surah-scoped sheet, fill in the surah the user implied ("recite
    // ayah 5" → this surah). Explicit surahs in the request still win.
    if (widget.surah != null && json['surah'] == null) {
      json = {...json, 'surah': widget.surah};
    }
    final routed = RoutedCommand.fromJson(json);
    switch (routed.command) {
      case final ReciteCommand cmd:
        await _reciteInBackground(cmd, routed.say);
        return true;
      case OpenSurahCommand() ||
            OpenTafsirCommand() ||
            SearchInSurahCommand() ||
            SearchQuranCommand():
        await CommandDispatcher(context, ref).run(
          routed,
          onInlineSearch: (query) => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => QuranSearchPage(initialQuery: query)),
          ),
        );
        return true;
      case final AskCommand cmd:
        // Not a command — answered as a question. Carry the source restriction
        // through to this turn's flow.
        _askTafsirOnly = cmd.tafsirOnly;
        return false;
      case NoneCommand():
        return false;
    }
  }

  /// Start recitation without leaving the sheet (so the user can keep asking).
  /// For a content-based recite ("read the ayah that says …") the ayah is first
  /// located by meaning, then recited.
  Future<void> _reciteInBackground(ReciteCommand cmd, String say) async {
    final store = ref.read(localContentProvider);
    await store.ensureLoaded();

    int surahNo;
    int from;
    bool continuous;
    String confirm = say;
    if (cmd.surah != null) {
      surahNo = cmd.surah!;
      if (surahNo < 1 || surahNo > 114) return;
      final count = store.getSurah(surahNo).ayat.length;
      from = (cmd.fromAyah != null && cmd.fromAyah! >= 1 && cmd.fromAyah! <= count)
          ? cmd.fromAyah!
          : 1;
      continuous = cmd.continuous;
    } else {
      // Locate the ayah described by [cmd.query], then recite that single ayah.
      final located = await ref.read(openAiClientProvider).locateAyat(
            model: ref.read(answerModelProvider),
            lang: widget.lang,
            question: cmd.query ?? '',
            surah: widget.surah,
          );
      if (!mounted) return;
      final hit = located.ayat.isNotEmpty ? located.ayat.first : null;
      if (hit == null || hit.surah < 1 || hit.surah > 114) {
        _toast(_noAyahToRecite);
        return;
      }
      surahNo = hit.surah;
      final count = store.getSurah(surahNo).ayat.length;
      from = (hit.ayah >= 1 && hit.ayah <= count) ? hit.ayah : 1;
      continuous = false; // a single located ayah
      confirm = '$surahNo:$from';
    }

    final count = store.getSurah(surahNo).ayat.length;
    final catalog = await ref.read(recitersProvider.future);
    if (!mounted) return;
    final reciter = ref.read(selectedReciterProvider) ?? catalog.defaultId;
    final ctrl = ref.read(audioControllerProvider.notifier);
    await ctrl.ensureLoaded(surahNo, count, reciter);
    await ctrl.playAyah(from, continuous: continuous);
    if (!mounted) return;
    setState(() => _recited = true);
    if (confirm.isNotEmpty) _toast(confirm);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<List<AiAyahMaterial>> _gather(List<AiAyahRef> refs) async {
    final store = ref.read(localContentProvider);
    await store.ensureLoaded();
    final tafsirDb = ref.read(tafsirDbProvider);
    final lexiconDb = ref.read(lexiconDbProvider);
    final bySurah = <int, List<int>>{};
    for (final r in refs) {
      (bySurah[r.surah] ??= []).add(r.ayah);
    }
    final out = <AiAyahMaterial>[];
    for (final entry in bySurah.entries) {
      final surah = store.getSurah(entry.key);
      out.addAll(await gatherAyahMaterial(
        surah: surah,
        ayahNumbers: entry.value,
        lang: widget.lang,
        tafsirDb: tafsirDb,
        lexiconDb: lexiconDb,
      ));
    }
    return out;
  }

  /// Part 2: fetch the out-of-tafsir answer from broader sources, honouring the
  /// out-of-tafsir mode — null when it should be skipped (tafsir-only) or the
  /// user declines (ask-first). With-sources always returns an answer.
  Future<AiAnswer?> _maybeBeyond(
      String question, List<AiTurn> history, List<AiCallUsage> usage) async {
    final mode = ref.read(outOfScopeModeProvider);
    if (mode == AppConfig.oosTafsirOnly) return null;
    if (mode == AppConfig.oosAskFirst) {
      final ok = await _confirmBeyond();
      if (ok != true) return null;
    }
    return ref.read(openAiClientProvider).answerBeyond(
          model: ref.read(oosAnswerModelProvider),
          lang: widget.lang,
          question: question,
          history: history,
          usage: usage,
        );
  }

  Future<bool?> _confirmBeyond() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Outside the provided tafsir'),
          content: const Text(
              'This isn\'t covered by the provided tafsir. Answer it from broader '
              'authentic Shia sources (flagged, with references)?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not now')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Answer')),
          ],
        ),
      );

  void _openAyah(AiAyahRef r) {
    // Push the reader OVER the sheet (don't pop it) so the back button returns
    // to this AI result. Pause any read-aloud while the reader is on top.
    _tts.stop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SurahReaderPage(number: r.surah, initialAyah: r.ayah),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final model = ref.watch(answerModelProvider);
    final count = _session.turns.length;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          widget.surah != null
                              ? 'Ask about Surah ${widget.surah}'
                              : 'Ask the Quran',
                          style: theme.textTheme.titleMedium),
                    ),
                    Chip(
                      label: Text('$count/${AskSession.maxQuestions}',
                          style: theme.textTheme.labelSmall),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 6),
                    Chip(
                      label: Text(model, style: theme.textTheme.labelSmall),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'AI finds the related ayat, then answers from their authentic '
                  'tafsir + Mufradat.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const Divider(height: 24),
                ..._thread(theme),
              ],
            ),
          ),
          if (_recited)
            _MiniPlayer(
              state: ref.watch(audioControllerProvider),
              onToggle: () =>
                  ref.read(audioControllerProvider.notifier).toggle(),
              onStop: () {
                ref.read(audioControllerProvider.notifier).stop();
                setState(() => _recited = false);
              },
            ),
          AiInputBar(
            controller: _input,
            focusNode: _focus,
            enabled: !_busy && !_full,
            hint: _full ? _fullHint : _inputHint,
            isRtl: _isRtl,
            lang: widget.lang,
            onSubmit: _run,
          ),
        ],
      ),
    );
  }

  List<Widget> _thread(ThemeData theme) {
    final widgets = <Widget>[];

    if (_session.isEmpty && _phase == _Phase.idle && _note.isEmpty) {
      widgets.add(_Hint(text: _idleHint));
    }

    // Committed turns.
    for (final t in _session.turns) {
      widgets.addAll(_turnView(theme, t));
    }

    // A note (off-topic question that located no ayat).
    if (_note.isNotEmpty) {
      widgets.add(const SizedBox(height: 16));
      widgets.add(_Hint(text: _note));
    }

    // The in-flight / errored turn.
    if (_phase != _Phase.idle) {
      widgets.add(const SizedBox(height: 18));
      widgets.add(_QuestionLabel(text: _pendingQuestion));
      // Progressive: once the out-of-tafsir answer is in, show it first so the
      // user can read it while the Quran/tafsir analysis is still composing.
      if (_pendingBeyond != null) {
        widgets.addAll(_beyondWidgets(theme, _pendingBeyond!.answer,
            _pendingBeyond!.example, _pendingBeyond!.references));
        widgets.add(const SizedBox(height: 16));
        widgets.add(const Divider(height: 1));
        widgets.add(const SizedBox(height: 16));
      }
      if (_pendingRefs.isNotEmpty) widgets.add(_relatedAyat(theme, _pendingRefs));
      if (_phase == _Phase.error) {
        widgets.add(_ErrorBox(message: '$_error', onRetry: _retry));
      } else {
        widgets.add(_Loading(
            label: _pendingBeyond != null
                ? 'Composing the Quran & tafsir analysis…'
                : switch (_phase) {
                    _Phase.locating => 'Finding related ayat…',
                    _Phase.gathering => 'Reading the tafsir…',
                    _ => 'Composing the answer…',
                  }));
      }
    }

    if (_full) {
      widgets.add(const SizedBox(height: 16));
      widgets.add(_Hint(text: _fullHint));
    }

    widgets.add(const SizedBox(height: 20));
    widgets.add(Text(
      'AI-generated from authentic tafsir (al-Mizan, Nemooneh, Noor) + Mufradat. '
      'Verify against the original sources.',
      style: theme.textTheme.bodySmall
          ?.copyWith(color: theme.colorScheme.outline),
    ));
    return widgets;
  }

  void _retry() {
    // Re-ask the pending question by putting it back in the box and running.
    _input.text = _pendingQuestion;
    setState(() {
      _phase = _Phase.idle;
      _error = null;
    });
    _run();
  }

  List<Widget> _turnView(ThemeData theme, AskTurn t) {
    final hasBeyond = t.beyondAnswer != null;
    return [
      const SizedBox(height: 18),
      _QuestionLabel(text: t.question),
      const SizedBox(height: 8),
      // When an out-of-tafsir answer exists, show it FIRST; the Quran/tafsir
      // section below then comments on it. Otherwise just the tafsir answer.
      if (hasBeyond) ...[
        ..._beyondSection(theme, t),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),
        ..._tafsirSection(theme, t, commentary: true),
      ] else
        ..._tafsirSection(theme, t, commentary: false),
      if (t.usage.isNotEmpty || t.extraCosts.isNotEmpty)
        UsageFooter(usage: t.usage, extraCosts: t.extraCosts),
    ];
  }

  /// The Quran + provided-tafsir answer. When [commentary] is true it follows an
  /// out-of-tafsir answer and comments on it.
  List<Widget> _tafsirSection(ThemeData theme, AskTurn t,
      {required bool commentary}) {
    return [
      if (t.refs.isNotEmpty) _relatedAyat(theme, t.refs),
      _SectionLabel(
          icon: Icons.menu_book_rounded,
          label: commentary ? _tafsirCommentLabel : _tafsirPartLabel),
      const SizedBox(height: 8),
      if (!t.inScope && !commentary) ...[
        _Hint(text: _tafsirNotCovered),
        const SizedBox(height: 8),
      ],
      _md(theme, t.answer),
      if (t.example != null) ...[
        const SizedBox(height: 12),
        _ExampleBox(child: _md(theme, t.example!)),
      ],
      if (t.references.isNotEmpty) ...[
        const SizedBox(height: 12),
        _References(label: _referencesLabel, items: t.references),
      ],
      PartAudioPlayer(source: t.answer),
    ];
  }

  /// The out-of-tafsir answer from broader (incl. non-Islamic) sources.
  List<Widget> _beyondSection(ThemeData theme, AskTurn t) =>
      _beyondWidgets(theme, t.beyondAnswer!, t.beyondExample, t.beyondReferences);

  List<Widget> _beyondWidgets(ThemeData theme, String answer, String? example,
      List<String> references) {
    return [
      _ScopeHint(label: _outOfScopeLabel),
      const SizedBox(height: 10),
      _md(theme, answer),
      if (example != null) ...[
        const SizedBox(height: 12),
        _ExampleBox(child: _md(theme, example)),
      ],
      if (references.isNotEmpty) ...[
        const SizedBox(height: 12),
        _References(label: _referencesLabel, items: references),
      ],
      PartAudioPlayer(source: answer),
    ];
  }

  Widget _relatedAyat(ThemeData theme, List<AiAyahRef> refs) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Related ayat', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in refs)
                ActionChip(
                  avatar: const Icon(Icons.menu_book_outlined, size: 16),
                  label: Text('${r.surah}:${r.ayah}'),
                  onPressed: () => _openAyah(r),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _md(ThemeData theme, String data) => Directionality(
        textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: MarkdownBody(
          data: data,
          selectable: true,
          styleSheet: MarkdownStyleSheet.fromTheme(theme)
              .copyWith(p: theme.textTheme.bodyLarge?.copyWith(height: 1.6)),
        ),
      );

  String get _inputHint => switch (widget.lang) {
        'fa' => 'سؤال خود را درباره قرآن بپرسید…',
        'nl' => 'Stel een vraag over de Koran…',
        _ => 'Ask a question about the Quran…',
      };

  String get _fullHint => switch (widget.lang) {
        'fa' =>
          'این گفتگو به ۵ سؤال رسید. برای ادامه، یک گفتگوی جدید آغاز کنید.',
        'nl' =>
          'Dit gesprek bereikte 5 vragen. Start een nieuw gesprek om door te gaan.',
        _ =>
          'This conversation reached 5 questions. Start a new conversation to continue.',
      };

  String get _idleHint => switch (widget.lang) {
        'fa' => 'سؤالی بپرسید؛ آیات مرتبط پیدا و بر پایهٔ تفسیر پاسخ داده می‌شود.',
        'nl' =>
          'Stel een vraag — de relevante ayat worden gezocht en beantwoord vanuit de tafsir.',
        _ =>
          'Ask a question — the related ayat are found and answered from their tafsir.',
      };

  String get _noRelatedAyat => switch (widget.lang) {
        'fa' => 'آیهٔ مرتبطی برای این سؤال یافت نشد.',
        'nl' => 'Geen gerelateerde ayat gevonden voor deze vraag.',
        _ => 'No closely related ayat were found for this question.',
      };

  String get _noAyahToRecite => switch (widget.lang) {
        'fa' => 'آیه‌ای برای قرائت یافت نشد.',
        'nl' => 'Geen ayah gevonden om te reciteren.',
        _ => 'Couldn\'t find an ayah to recite for that.',
      };

  String get _outOfScopeLabel => switch (widget.lang) {
        'fa' => 'پاسخ بر پایهٔ منابع بیرونی (خارج از تفاسیر ارائه‌شده)',
        'nl' => 'Antwoord op basis van externe bronnen (buiten de tafsir)',
        _ => 'Answer from broader sources (outside the provided tafsir)',
      };

  String get _tafsirPartLabel => switch (widget.lang) {
        'fa' => 'بر پایهٔ قرآن و تفاسیر',
        'nl' => 'Op basis van de Koran en tafsir',
        _ => 'From the Quran & tafsir',
      };

  String get _tafsirCommentLabel => switch (widget.lang) {
        'fa' => 'بر پایهٔ قرآن و تفاسیر (در بررسی پاسخ بالا)',
        'nl' => 'Vanuit de Koran en tafsir (toetsing van bovenstaand antwoord)',
        _ => 'From the Quran & tafsir (reviewing the answer above)',
      };

  String get _tafsirNotCovered => switch (widget.lang) {
        'fa' => 'تفاسیر ارائه‌شده به‌طور مستقیم به این پرسش نمی‌پردازند.',
        'nl' => 'De meegeleverde tafsir behandelt deze vraag niet rechtstreeks.',
        _ => 'The provided tafsir doesn\'t directly address this question.',
      };

  String get _referencesLabel => switch (widget.lang) {
        'fa' => 'منابع',
        'nl' => 'Bronnen',
        _ => 'References',
      };
}

class _QuestionLabel extends StatelessWidget {
  const _QuestionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.person_outline, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Inline now-playing/stop control for a recitation started from this sheet,
/// shown because the home Ask sheet has no reader PlayerBar underneath it.
class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer(
      {required this.state, required this.onToggle, required this.onStop});
  final AudioState state;
  final VoidCallback onToggle;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = state.surah != null && state.currentAyah != null
        ? 'Reciting ${state.surah}:${state.currentAyah}'
        : 'Recitation';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.graphic_eq, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
          ),
          if (state.loading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              tooltip: state.playing ? 'Pause' : 'Play',
              icon: Icon(state.playing
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded),
              color: cs.primary,
              onPressed: onToggle,
            ),
          IconButton(
            tooltip: 'Stop',
            icon: const Icon(Icons.stop_rounded),
            color: cs.primary,
            onPressed: onStop,
          ),
        ],
      ),
    );
  }
}

/// A small section header dividing the two answer parts (Quran+tafsir vs.
/// broader sources).
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Text(label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: cs.primary, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _ScopeHint extends StatelessWidget {
  const _ScopeHint({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.tertiary.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.travel_explore, size: 18, color: cs.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onTertiaryContainer,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _References extends StatelessWidget {
  const _References({required this.label, required this.items});
  final String label;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.menu_book_outlined, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Text(label,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        for (final r in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Icon(Icons.circle, size: 5, color: cs.outline),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(r,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ExampleBox extends StatelessWidget {
  const _ExampleBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.secondary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 16, color: cs.secondary),
              const SizedBox(width: 6),
              Text('Example',
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.secondary, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.tips_and_updates_outlined, size: 20, color: cs.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 36),
          const SizedBox(height: 10),
          Text(message,
              textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
