import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import 'ai_settings_controller.dart';

/// App settings. For now: the OpenAI model used by the AI tafsir summary.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(aiModelProvider);
    final cs = Theme.of(context).colorScheme;
    final keyConfigured = AppConfig.openAiApiKey.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('AI summary model',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: cs.primary)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Model used when you tap the AI button in a surah to summarize the '
              'tafsir and word meanings of the ayat on screen.',
            ),
          ),
          for (final m in AppConfig.aiModels)
            ListTile(
              leading: Icon(m == selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              title: Text(m),
              subtitle:
                  m == AppConfig.defaultAiModel ? const Text('Default') : null,
              selected: m == selected,
              onTap: () => ref.read(aiModelProvider.notifier).state = m,
            ),
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
}
