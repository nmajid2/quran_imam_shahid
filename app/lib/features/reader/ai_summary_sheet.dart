import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../data/models/surah.dart';
import '../ai/ai_cost_pending.dart';
import '../ai/ai_input_bar.dart';
import '../ai/ai_usage.dart';
import '../ai/ai_usage_footer.dart';
import '../ai/ask_session.dart';
import '../ai/ask_sessions_controller.dart';
import '../ai/openai_client.dart';
import '../ai/part_audio_player.dart';
import '../ai/tts_controller.dart';
import '../settings/ai_settings_controller.dart';
import 'ai_summary.dart';

/// One asked question and its (pending / answered / failed) reply.
class _Turn {
  _Turn(this.question, {this.fromUser = false});
  final String question;
  final bool fromUser; // typed by the user vs. tapped from a suggestion
  String? answer;
  String? example; // a clarifying example, only when the AI deems it needed
  bool inScope = true; // false → answer drew on sources beyond the tafsir material
  List<String> references = const []; // sources cited for an out-of-scope answer
  List<AiCallUsage> usage = const []; // token usage for this turn's model calls
  List<AiExtraCost> extraCosts = const []; // STT/TTS costs folded into this turn
  Object? error;
  bool loading = true;
}

/// Bottom sheet that summarizes the on-screen / selected ayat, then lets the user
/// drill in: round 1 returns a summary + key points + up to 5 questions; tapping a
/// question runs a stateless round-2 call (re-sending the full material + questions
/// + selection) whose answer (and any new follow-up questions) appears inline.
class AiSummarySheet extends ConsumerStatefulWidget {
  const AiSummarySheet({
    super.key,
    required this.surah,
    required this.ayahNumbers,
    required this.lang,
  });
  final Surah surah;
  final List<int> ayahNumbers;
  final String lang;

  @override
  ConsumerState<AiSummarySheet> createState() => _AiSummarySheetState();
}

class _AiSummarySheetState extends ConsumerState<AiSummarySheet> {
  late Future<AiSummary> _summaryFuture;
  List<AiAyahMaterial>? _material; // gathered once, reused for every round
  AiSummary? _summary;
  final List<_Turn> _turns = [];
  // Lazily-created history session: the per-ayah Q&A is saved so it's reachable
  // from the home "Ask AI" history like every other AI conversation.
  AskSession? _historySession;
  final Set<String> _askedKeys = {}; // normalized keys of questions already asked
  List<String> _suggested = [];
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  // Captured in initState so dispose() never calls ref.read (illegal there).
  late final TtsController _tts;

  bool get _isRtl => widget.lang == 'fa';

  /// Material is gathered up-front in [_runSummary]; once it exists the user can
  /// ask their own questions (even before the summary call returns).
  bool get _ready => _material != null && _material!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _tts = ref.read(ttsControllerProvider.notifier);
    _summaryFuture = _runSummary();
  }

  @override
  void dispose() {
    _tts.stop();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<AiSummary> _runSummary() async {
    final material = _material ??= await gatherAyahMaterial(
      surah: widget.surah,
      ayahNumbers: widget.ayahNumbers,
      lang: widget.lang,
      tafsirDb: ref.read(tafsirDbProvider),
      lexiconDb: ref.read(lexiconDbProvider),
    );
    if (material.isEmpty) {
      throw AiException('No tafsir or word data found for these ayat.');
    }
    // Material is ready → enable the input bar (the outer Column is built once,
    // so it needs a rebuild that the FutureBuilder alone wouldn't trigger).
    if (mounted) setState(() {});
    final s = await ref.read(openAiClientProvider).summarize(
          model: ref.read(answerModelProvider),
          lang: widget.lang,
          ayat: material,
        );
    _summary = s;
    _suggested = [];
    for (final q in s.questions) {
      _addSuggestion(q);
    }
    return s;
  }

  /// Normalized comparison key: catches the same question re-emitted with only
  /// whitespace / trailing-punctuation differences (incl. the Persian `؟`).
  String _qKey(String q) => q
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[\s?؟.!،,]+$'), '');

  /// Add a question to the suggestion list unless an equivalent one was already
  /// asked or is already suggested.
  void _addSuggestion(String q) {
    final k = _qKey(q);
    if (k.isEmpty) return;
    if (_askedKeys.contains(k)) return;
    if (_suggested.any((s) => _qKey(s) == k)) return;
    _suggested.add(q);
  }

  void _retrySummary() => setState(() => _summaryFuture = _runSummary());

  void _ask(String question, {bool fromUser = false, bool fromVoice = false}) {
    final k = _qKey(question);
    if (k.isEmpty || _askedKeys.contains(k) || _material == null) return;
    _askedKeys.add(k);
    final turn = _Turn(question, fromUser: fromUser);
    setState(() {
      _turns.add(turn);
      _suggested.removeWhere((s) => _qKey(s) == k);
    });
    _runTurn(turn, fromVoice: fromVoice);
  }

  /// Send the user's own typed/spoken question as the next turn in the thread.
  /// Its answer sees the full prior conversation via [_historyBefore].
  void _submit({bool fromVoice = false}) {
    final q = _input.text.trim();
    if (q.isEmpty || !_ready) return;
    _input.clear();
    _inputFocus.unfocus();
    _ask(q, fromUser: true, fromVoice: fromVoice);
  }

  String get _inputHint {
    switch (widget.lang) {
      case 'fa':
        return 'سؤال خود را بپرسید…';
      case 'nl':
        return 'Stel je eigen vraag…';
      default:
        return 'Ask your own question…';
    }
  }

  String get _outOfScopeLabel {
    switch (widget.lang) {
      case 'fa':
        return 'خارج از تفاسیر ارائه‌شده — پاسخ بر پایهٔ منابع بیرونی';
      case 'nl':
        return 'Buiten de meegeleverde tafsir — op basis van externe bronnen';
      default:
        return 'Outside the provided tafsir — based on external sources';
    }
  }

  String get _referencesLabel {
    switch (widget.lang) {
      case 'fa':
        return 'منابع';
      case 'nl':
        return 'Bronnen';
      default:
        return 'References';
    }
  }

  Future<void> _runTurn(_Turn turn, {bool fromVoice = false}) async {
    setState(() {
      turn.loading = true;
      turn.error = null;
    });
    // Token usage across this turn's model calls, plus the non-token costs
    // (voice STT/refine from the input bar) the pending bucket holds for it.
    final usage = <AiCallUsage>[];
    final extraCosts = <AiExtraCost>[];
    {
      final pending = ref.read(pendingAiCostProvider.notifier).drain();
      usage.addAll(pending.chat);
      extraCosts.addAll(pending.extra);
    }
    try {
      final client = ref.read(openAiClientProvider);
      final hist = _historyBefore(turn);
      // In-scope attempt: answer strictly from the open ayat's material.
      final attempt = await client.answer(
            model: ref.read(answerModelProvider),
            lang: widget.lang,
            ayat: _material!,
            question: turn.question,
            summary: _summary?.summary,
            suggestedQuestions: _summary?.questions ?? const [],
            history: hist,
            usage: usage,
          );
      // If the material doesn't cover it, resolve per the out-of-tafsir mode.
      final a = attempt.inScope
          ? attempt
          : await _resolveOutOfScope(turn.question, hist, attempt, usage);
      if (!mounted) return;
      final readAloud =
          fromVoice && ref.read(ttsEnabledProvider) && a.answer.trim().isNotEmpty;
      if (readAloud) {
        final p = plainForSpeech(a.answer);
        if (p.isNotEmpty) {
          extraCosts.add(AiExtraCost(
              kind: 'tts', costUsd: estimateTtsCost(p).costUsd, estimated: true));
        }
      }
      setState(() {
        turn.answer = a.answer;
        turn.example = a.example;
        turn.inScope = a.inScope;
        turn.references = a.references;
        turn.usage = usage;
        turn.extraCosts = extraCosts;
        turn.loading = false;
        for (final q in a.questions) {
          _addSuggestion(q);
        }
      });
      _saveToHistory(turn);
      if (readAloud) {
        final t = plainForSpeech(a.answer);
        ref.read(ttsControllerProvider.notifier).play(ttsIdFor(t), t);
      }
    } catch (e) {
      setState(() {
        turn.error = e;
        turn.loading = false;
      });
    }
  }

  /// Persist a completed Q&A turn to the shared "Ask the Quran" history, tagged
  /// with this surah + ayah range so it's labeled in the history list.
  void _saveToHistory(_Turn turn) {
    final answer = turn.answer;
    if (answer == null || answer.isEmpty) return;
    final ctrl = ref.read(askSessionsProvider.notifier);
    _historySession ??= ctrl.newSession(
      surah: widget.surah.number,
      ayah: widget.ayahNumbers.first,
      ayahEnd: widget.ayahNumbers.last,
    );
    ctrl.addTurn(
      _historySession!,
      AskTurn(
        question: turn.question,
        answer: answer,
        example: turn.example,
        inScope: turn.inScope,
        references: turn.references,
        refs: [
          for (final n in widget.ayahNumbers)
            (surah: widget.surah.number, ayah: n)
        ],
        usage: turn.usage,
        extraCosts: turn.extraCosts,
      ),
    );
  }

  /// The attempt found the question outside the provided tafsir. Honour the
  /// out-of-tafsir mode: keep the "not covered" note (tafsir-only / declined), or
  /// answer from broader sources via the OOS model (with-sources / confirmed).
  Future<AiAnswer> _resolveOutOfScope(String question, List<AiTurn> history,
      AiAnswer attempt, List<AiCallUsage> usage) async {
    final mode = ref.read(outOfScopeModeProvider);
    if (mode == AppConfig.oosTafsirOnly) return attempt;
    if (mode == AppConfig.oosAskFirst) {
      final ok = await _confirmBeyond();
      if (ok != true) return attempt;
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

  List<AiTurn> _historyBefore(_Turn turn) {
    final out = <AiTurn>[];
    for (final t in _turns) {
      if (identical(t, turn)) break;
      if (t.answer != null) out.add((question: t.question, answer: t.answer!));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final model = ref.watch(answerModelProvider);
    final first = widget.ayahNumbers.first;
    final last = widget.ayahNumbers.last;
    final range = first == last ? '$first' : '$first–$last';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
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
                child: Text('AI tafsir summary',
                    style: theme.textTheme.titleMedium),
              ),
              Chip(
                label: Text(model, style: theme.textTheme.labelSmall),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('Surah ${widget.surah.number} · ayat $range',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
          const Divider(height: 24),
          FutureBuilder<AiSummary>(
            future: _summaryFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const _Loading(
                    label: 'Reading the tafsir and asking the AI…');
              }
              if (snap.hasError) {
                return _ErrorBox(
                    message: '${snap.error}', onRetry: _retrySummary);
              }
              final s = snap.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _md(theme, s.summary),
                  if (s.keyPoints.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Key points', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    _bullets(theme, s.keyPoints),
                  ],
                  ..._qaSection(theme),
                  const SizedBox(height: 24),
                  Text(
                    'AI-generated from authentic tafsir (al-Mizan, Nemooneh, Noor) '
                    '+ Mufradat. Verify against the original sources.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              );
            },
          ),
              ],
            ),
          ),
          AiInputBar(
            controller: _input,
            focusNode: _inputFocus,
            enabled: _ready,
            hint: _ready ? _inputHint : 'Loading…',
            isRtl: _isRtl,
            lang: widget.lang,
            onSubmit: _submit,
          ),
        ],
      ),
    );
  }

  List<Widget> _qaSection(ThemeData theme) {
    return [
      // Answered / pending turns.
      for (final t in _turns) ...[
        const SizedBox(height: 20),
        _QuestionLabel(text: t.question, fromUser: t.fromUser),
        const SizedBox(height: 8),
        if (t.loading)
          const _Loading(label: 'Thinking…')
        else if (t.error != null)
          _ErrorBox(message: '${t.error}', onRetry: () => _runTurn(t))
        else ...[
          if (!t.inScope) ...[
            _ScopeHint(label: _outOfScopeLabel),
            const SizedBox(height: 10),
          ],
          _md(theme, t.answer ?? ''),
          if (t.example != null) ...[
            const SizedBox(height: 12),
            _ExampleBox(child: _md(theme, t.example!)),
          ],
          if (t.references.isNotEmpty) ...[
            const SizedBox(height: 12),
            _References(label: _referencesLabel, items: t.references),
          ],
          PartAudioPlayer(source: t.answer ?? ''),
          if (t.usage.isNotEmpty || t.extraCosts.isNotEmpty)
            UsageFooter(usage: t.usage, extraCosts: t.extraCosts),
        ],
      ],
      // Suggested questions to ask next.
      if (_suggested.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text(_turns.isEmpty ? 'Questions' : 'Ask a follow-up',
            style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final q in _suggested)
          _QuestionTile(text: q, onTap: () => _ask(q)),
      ],
    ];
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

  Widget _bullets(ThemeData theme, List<String> points) => Directionality(
        textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final p in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(Icons.circle,
                          size: 6, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(p,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(height: 1.5)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.help_outline, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(text,
                        style: Theme.of(context).textTheme.bodyMedium)),
                Icon(Icons.chevron_right, size: 18, color: cs.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinned footer where the user types their own follow-up question. Disabled
/// until the ayah material is ready; submitting sends the next thread turn.
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

/// The sources the AI cited for an (out-of-scope) answer.
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
                  child:
                      Icon(Icons.circle, size: 5, color: cs.outline),
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

/// A subtle callout that frames a clarifying example under an answer.
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
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: cs.secondary, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _QuestionLabel extends StatelessWidget {
  const _QuestionLabel({required this.text, this.fromUser = false});
  final String text;
  final bool fromUser;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(fromUser ? Icons.person_outline : Icons.question_answer_outlined,
            size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
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
