import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../ai/tts_controller.dart';
import 'ai_settings_controller.dart';

/// App settings: the three role-specific AI models and the out-of-tafsir mode.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final keyConfigured = AppConfig.openAiApiKey.trim().isNotEmpty;

    final answer = ref.watch(answerModelProvider);
    final oosAnswer = ref.watch(oosAnswerModelProvider);
    final classify = ref.watch(classifyModelProvider);
    final refine = ref.watch(refineModelProvider);
    final oos = ref.watch(outOfScopeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _ModelSection(
            title: 'Answer model',
            blurb: 'Writes the actual answers and tafsir summaries — the heaviest '
                'task. Pick a stronger model here for deeper replies.',
            selected: answer,
            onSelect: (m) => ref.read(answerModelProvider.notifier).state = m,
            defaultModel: AppConfig.defaultAnswerModel,
          ),
          const Divider(height: 24),
          _ModelSection(
            title: 'Out-of-scope answer model',
            blurb: 'Used when a question is NOT covered by the provided tafsir and '
                'is answered from broader authentic sources (the question is sent '
                'on its own, with no ayah/tafsir). Pick a stronger model here.',
            selected: oosAnswer,
            onSelect: (m) => ref.read(oosAnswerModelProvider.notifier).state = m,
            defaultModel: AppConfig.defaultOosAnswerModel,
          ),
          const Divider(height: 24),
          _ModelSection(
            title: 'Command model',
            blurb: 'Understands a typed/spoken request on the home page and decides '
                'what to do (open a surah, search, ask…). A fast model is fine.',
            selected: classify,
            onSelect: (m) => ref.read(classifyModelProvider.notifier).state = m,
            defaultModel: AppConfig.defaultClassifyModel,
          ),
          const Divider(height: 24),
          _ModelSection(
            title: 'Voice-cleanup model',
            blurb: 'Fixes speech-to-text typos and misheard words against the '
                'Quran/Islamic context before your spoken question is used.',
            selected: refine,
            onSelect: (m) => ref.read(refineModelProvider.notifier).state = m,
            defaultModel: AppConfig.defaultRefineModel,
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text('When a question is outside the tafsir',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: cs.primary)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
                'How the assistant should handle a question the provided authentic '
                'tafsir does not cover.'),
          ),
          for (final m in AppConfig.outOfScopeModes)
            RadioListTile<String>(
              value: m,
              groupValue: oos,
              onChanged: (v) =>
                  ref.read(outOfScopeModeProvider.notifier).state = v!,
              title: Text(_oosTitle(m)),
              subtitle: Text(_oosBlurb(m)),
            ),
          const Divider(height: 24),
          const _VoiceReadbackSection(),
          const Divider(height: 24),
          ListTile(
            leading: Icon(
              keyConfigured ? Icons.key : Icons.key_off_outlined,
              color: keyConfigured ? cs.primary : cs.error,
            ),
            title: const Text('OpenAI key'),
            subtitle: Text(keyConfigured
                ? 'Configured at build time.'
                : 'Not set — rebuild with --dart-define=OPENAI_API_KEY=sk-…'),
          ),
        ],
      ),
    );
  }

  String _oosTitle(String m) => switch (m) {
        AppConfig.oosTafsirOnly => 'Tafsir only',
        AppConfig.oosAskFirst => 'Ask before answering',
        _ => 'Answer with sources',
      };

  String _oosBlurb(String m) => switch (m) {
        AppConfig.oosTafsirOnly =>
          'Answer only from the provided tafsir; if it is not covered, say so.',
        AppConfig.oosAskFirst =>
          'Warn that it is outside the tafsir and ask before answering from '
              'broader authentic sources.',
        _ =>
          'Answer from authentic Shia scholarship beyond the tafsir, flagged and '
              'with precise references.',
      };
}

/// Read-answers-aloud (TTS) settings: enable toggle + narrator picker with a
/// per-voice sample preview and a supported-languages note.
class _VoiceReadbackSection extends ConsumerWidget {
  const _VoiceReadbackSection();

  static String _sample(String lang) => switch (lang) {
        'fa' => 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِیمِ. این نمونه‌ای از صدای گوینده است.',
        'nl' => 'In de naam van God. Dit is een voorbeeld van de verteller.',
        _ => 'In the name of God. This is a sample of the narrator\'s voice.',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabled = ref.watch(ttsEnabledProvider);
    final voice = ref.watch(ttsVoiceProvider);
    final speed = ref.watch(ttsSpeedProvider);
    final tts = ref.watch(ttsControllerProvider);
    final lang = ref.watch(languageProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text('Read answers aloud',
              style: theme.textTheme.titleSmall?.copyWith(color: cs.primary)),
        ),
        SwitchListTile(
          value: enabled,
          onChanged: (v) => ref.read(ttsEnabledProvider.notifier).state = v,
          title: const Text('Speak answers to voice questions'),
          subtitle: const Text(
              'When you ask by voice, the answer is read back in the narrator '
              'you pick below.'),
        ),
        if (enabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Icon(Icons.speed, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text('Reading speed', style: theme.textTheme.bodyMedium),
                const Spacer(),
                Text('${speed.toStringAsFixed(2)}×',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: cs.primary)),
              ],
            ),
          ),
          Slider(
            value: speed,
            min: AppConfig.ttsSpeedMin,
            max: AppConfig.ttsSpeedMax,
            divisions: 6, // 0.5 → 2.0 in 0.25 steps
            label: '${speed.toStringAsFixed(2)}×',
            onChanged: (v) => ref.read(ttsSpeedProvider.notifier).state =
                double.parse(v.toStringAsFixed(2)),
          ),
          for (final v in AppConfig.ttsVoices)
            ListTile(
              dense: true,
              leading: Icon(v.id == voice
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              title: Text(v.label),
              subtitle: Text(v.blurb),
              selected: v.id == voice,
              onTap: () => ref.read(ttsVoiceProvider.notifier).state = v.id,
              trailing: Builder(builder: (_) {
                final previewId = 'preview:${v.id}';
                final previewing =
                    tts.currentId == previewId || tts.loadingId == previewId;
                return IconButton(
                  tooltip: 'Play sample',
                  icon: previewing
                      ? const Icon(Icons.stop_circle_outlined)
                      : const Icon(Icons.play_circle_outline),
                  onPressed: () {
                    final ctrl = ref.read(ttsControllerProvider.notifier);
                    if (previewing) {
                      ctrl.stop();
                    } else {
                      ref.read(ttsVoiceProvider.notifier).state = v.id;
                      ctrl.play(previewId, _sample(lang), voice: v.id);
                    }
                  },
                );
              }),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: cs.outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(AppConfig.ttsLangNote,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ModelSection extends StatelessWidget {
  const _ModelSection({
    required this.title,
    required this.blurb,
    required this.selected,
    required this.onSelect,
    required this.defaultModel,
  });
  final String title;
  final String blurb;
  final String selected;
  final ValueChanged<String> onSelect;
  final String defaultModel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: cs.primary)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(blurb),
        ),
        for (final m in AppConfig.aiModels)
          ListTile(
            dense: true,
            leading: Icon(m == selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked),
            title: Text(m),
            subtitle: m == defaultModel ? const Text('Default') : null,
            selected: m == selected,
            onTap: () => onSelect(m),
          ),
      ],
    );
  }
}
