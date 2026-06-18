import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../reader/surah_reader_page.dart';

class SurahListPage extends ConsumerWidget {
  const SurahListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surahs = ref.watch(surahListProvider);
    final lang = ref.watch(languageProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quran Imam Shahid'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.translate),
            onSelected: (l) =>
                ref.read(languageProvider.notifier).state = l,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'fa', child: Text('فارسی')),
              PopupMenuItem(value: 'en', child: Text('English')),
              PopupMenuItem(value: 'nl', child: Text('Nederlands')),
            ],
          ),
        ],
      ),
      body: surahs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: 'Could not reach the gateway.\n$e',
          onRetry: () => ref.invalidate(surahListProvider),
        ),
        data: (list) => ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final s = list[i];
            return ListTile(
              leading: CircleAvatar(child: Text('${s.number}')),
              title: Text(s.localizedName(lang)),
              subtitle: Text('${s.nameTranslit} · ${s.ayahCount} ayat'),
              trailing: Text(
                s.nameAr,
                style: const TextStyle(fontSize: 20),
                textDirection: TextDirection.rtl,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SurahReaderPage(number: s.number),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
