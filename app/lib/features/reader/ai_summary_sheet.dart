import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/surah.dart';
import '../ai/openai_client.dart';
import '../settings/ai_settings_controller.dart';
import 'ai_summary.dart';

/// One asked question and its (pending / answered / failed) reply.
class _Turn {
  _Turn(this.question);
  final String question;
  String? answer;
  String? example; // a clarifying example, only when the AI deems it needed
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
  final Set<String> _asked = {};
  List<String> _suggested = [];

  bool get _isRtl => widget.lang == 'fa';

  @override
  void initState() {
    super.initState();
    _summaryFuture = _runSummary();
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
    final s = await ref.read(openAiClientProvider).summarize(
          model: ref.read(aiModelProvider),
          lang: widget.lang,
          ayat: material,
        );
    _summary = s;
    _suggested = List.of(s.questions);
    return s;
  }

  void _retrySummary() => setState(() => _summaryFuture = _runSummary());

  void _ask(String question) {
    if (_asked.contains(question) || _material == null) return;
    _asked.add(question);
    final turn = _Turn(question);
    setState(() {
      _turns.add(turn);
      _suggested.remove(question);
    });
    _runTurn(turn);
  }

  Future<void> _runTurn(_Turn turn) async {
    setState(() {
      turn.loading = true;
      turn.error = null;
    });
    try {
      final a = await ref.read(openAiClientProvider).answer(
            model: ref.read(aiModelProvider),
            lang: widget.lang,
            ayat: _material!,
            question: turn.question,
            summary: _summary?.summary,
            suggestedQuestions: _summary?.questions ?? const [],
            history: _historyBefore(turn),
          );
      setState(() {
        turn.answer = a.answer;
        turn.example = a.example;
        turn.loading = false;
        for (final q in a.questions) {
          if (!_asked.contains(q) && !_suggested.contains(q)) _suggested.add(q);
        }
      });
    } catch (e) {
      setState(() {
        turn.error = e;
        turn.loading = false;
      });
    }
  }

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
    final model = ref.watch(aiModelProvider);
    final first = widget.ayahNumbers.first;
    final last = widget.ayahNumbers.last;
    final range = first == last ? '$first' : '$first–$last';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
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
    );
  }

  List<Widget> _qaSection(ThemeData theme) {
    return [
      // Answered / pending turns.
      for (final t in _turns) ...[
        const SizedBox(height: 20),
        _QuestionLabel(text: t.question),
        const SizedBox(height: 8),
        if (t.loading)
          const _Loading(label: 'Thinking…')
        else if (t.error != null)
          _ErrorBox(message: '${t.error}', onRetry: () => _runTurn(t))
        else ...[
          _md(theme, t.answer ?? ''),
          if (t.example != null) ...[
            const SizedBox(height: 12),
            _ExampleBox(child: _md(theme, t.example!)),
          ],
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
  const _QuestionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.question_answer_outlined, size: 18, color: cs.primary),
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
