import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';

/// Per-ayah tafsir from the authentic Shia sources (al-Mizan, Nemooneh, Noor).
/// The user picks which tafsir to read; content is rendered from Markdown.
class TafsirSheet extends ConsumerWidget {
  const TafsirSheet(
      {super.key, required this.surah, required this.ayah, required this.lang});
  final int surah;
  final int ayah;
  final String lang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(tafsirsProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => catalogAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('No tafsir available.\n$e')),
        data: (catalog) {
          if (catalog.editions.isEmpty) {
            return const Center(child: Text('No tafsir sources configured.'));
          }
          final selectedId =
              ref.watch(selectedTafsirProvider) ?? catalog.editions.first.id;
          final theme = Theme.of(context);

          return ListView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
              Text('Tafsir · $surah:$ayah', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              // Source picker.
              Wrap(
                spacing: 8,
                children: catalog.editions.map((e) {
                  return ChoiceChip(
                    label: Text(e.localizedName(lang)),
                    selected: e.id == selectedId,
                    onSelected: (_) =>
                        ref.read(selectedTafsirProvider.notifier).state = e.id,
                  );
                }).toList(),
              ),
              const SizedBox(height: 4),
              Text(
                catalog.byId(selectedId)?.author ?? '',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const Divider(height: 24),
              _TafsirBody(tafsirId: selectedId, surah: surah, ayah: ayah),
            ],
          );
        },
      ),
    );
  }
}

class _TafsirBody extends ConsumerWidget {
  const _TafsirBody(
      {required this.tafsirId, required this.surah, required this.ayah});
  final String tafsirId;
  final int surah;
  final int ayah;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (id: tafsirId, surah: surah, ayah: ayah);
    final contentAsync = ref.watch(tafsirContentProvider(key));
    final theme = Theme.of(context);

    return contentAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('No commentary for this ayah.\n$e',
            style: theme.textTheme.bodyMedium),
      ),
      data: (c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Passage notice — these tafsirs comment on a range of ayat, not one.
          if (c.coversMultiple)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: theme.colorScheme.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This commentary covers ayat ${c.ayahStart}–${c.ayahEnd} together.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          // Persian commentary — right-to-left, with Arabic code-fences styled.
          Directionality(
            textDirection: TextDirection.rtl,
            child: MarkdownBody(
              data: _cleanMarkdown(c.content),
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: theme.textTheme.bodyLarge?.copyWith(height: 1.7),
                code: AppTheme.arabic.copyWith(fontSize: 20, height: 1.9),
                codeblockDecoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            c.attribution,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  /// Tidy the source Markdown for display: drop the invisible `<span>` ayah
  /// anchors (rendered as literal text by the Markdown widget) and the
  /// ```arabic / ```farsi info-strings (kept as plain fenced blocks).
  static String _cleanMarkdown(String md) {
    return md
        .replaceAll(RegExp(r'<span[^>]*>\s*</span>'), '')
        .replaceAll(RegExp(r'```\s*(arabic|farsi)\b'), '```');
  }
}
