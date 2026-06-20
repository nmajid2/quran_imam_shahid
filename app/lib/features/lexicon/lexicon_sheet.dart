import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';

/// Word-lexicon sheet: shown when a word in an ayah is tapped. Resolves the
/// word's Arabic root and shows its lexicon entries (Mufradat now; al-Tahqiq later).
class LexiconSheet extends ConsumerWidget {
  const LexiconSheet({super.key, required this.word, required this.lang});
  final String word;
  final String lang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lookup = ref.watch(lexiconLookupProvider(word));
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, controller) => lookup.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lexicon unavailable.\n$e')),
        data: (lk) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            // The tapped word + its root.
            Center(
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Text(word,
                    style: AppTheme.arabic.copyWith(
                        fontSize: 28, color: theme.colorScheme.primary)),
              ),
            ),
            const SizedBox(height: 8),
            if (lk.root != null)
              Center(
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Chip(
                    label: Text('الجذر: ${lk.root}'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            const Divider(height: 28),
            if (!lk.hasEntry)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    lk.root == null
                        ? 'No root found for this word (likely a particle).'
                        : 'No lexicon entry for this root yet.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ...lk.entries.map((e) => _EntryBlock(entry: e, lang: lang)),
          ],
        ),
      ),
    );
  }
}

class _EntryBlock extends StatelessWidget {
  const _EntryBlock({required this.entry, required this.lang});
  final dynamic entry; // LexiconEntry
  final String lang;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = entry.book;
    final title = book == null
        ? entry.bookId
        : (lang == 'fa' ? book.nameFa : '${book.name} — ${book.author}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary)),
        const SizedBox(height: 8),
        Directionality(
          textDirection: TextDirection.rtl,
          child: SelectableText(
            entry.content as String,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.8),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
