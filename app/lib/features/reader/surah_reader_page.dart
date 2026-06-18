import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/models/surah.dart';
import 'tafsir_sheet.dart';

class SurahReaderPage extends ConsumerWidget {
  const SurahReaderPage({super.key, required this.number});
  final int number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surah = ref.watch(surahProvider(number));
    final lang = ref.watch(languageProvider);

    return Scaffold(
      appBar: AppBar(
        title: surah.maybeWhen(
          data: (s) => Text(s.nameTranslit),
          orElse: () => Text('Surah $number'),
        ),
      ),
      body: surah.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (s) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: s.ayat.length,
          separatorBuilder: (_, __) => const Divider(height: 32),
          itemBuilder: (_, i) => _AyahTile(surah: s, ayah: s.ayat[i], lang: lang),
        ),
      ),
    );
  }
}

class _AyahTile extends StatelessWidget {
  const _AyahTile({required this.surah, required this.ayah, required this.lang});
  final Surah surah;
  final Ayah ayah;
  final String lang;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(radius: 14, child: Text('${ayah.ayah}', style: const TextStyle(fontSize: 12))),
            const Spacer(),
            IconButton(
              tooltip: 'Tafsir',
              icon: const Icon(Icons.menu_book_outlined),
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => TafsirSheet(surah: surah.number, ayah: ayah.ayah, lang: lang),
              ),
            ),
            const Icon(Icons.play_circle_outline), // hook up audio in Phase 1/2
          ],
        ),
        const SizedBox(height: 8),
        // Arabic, right-to-left.
        Directionality(
          textDirection: TextDirection.rtl,
          child: Text(ayah.textAr, style: AppTheme.arabic),
        ),
        const SizedBox(height: 8),
        Directionality(
          textDirection: lang == 'fa' ? TextDirection.rtl : TextDirection.ltr,
          child: Text(
            ayah.translation(lang),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}
