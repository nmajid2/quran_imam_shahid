import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Per-ayah tafsir, fetched from the gateway with mandatory source citations.
class TafsirSheet extends ConsumerWidget {
  const TafsirSheet({super.key, required this.surah, required this.ayah, required this.lang});
  final int surah;
  final int ayah;
  final String lang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final future = ref.read(apiClientProvider).tafsir(surah, ayah, lang);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (context, controller) => FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('No tafsir available.\n${snap.error}'));
          }
          final data = snap.data!;
          final sources = (data['sources'] as List).cast<Map<String, dynamic>>();
          return ListView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
              Text('Tafsir · $surah:$ayah',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              _ConfidenceChip(confidence: data['confidence'] as String),
              const SizedBox(height: 12),
              Text(data['text'] as String,
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 20),
              if (sources.isNotEmpty) ...[
                Text('Sources', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                ...sources.map((s) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.bookmark_border),
                      title: Text('${s['book']} — ${s['author']}'),
                      subtitle: Text(s['ref'] as String),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.confidence});
  final String confidence;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (confidence) {
      'grounded' => ('Grounded in sources', Colors.green),
      'partial' => ('Partial', Colors.orange),
      _ => ('Insufficient basis — consult a scholar', Colors.red),
    };
    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color),
    );
  }
}
