import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/reciter.dart';
import 'audio_controller.dart';

/// Persistent playback bar shown at the bottom of the reader. Controls the whole
/// surah (play/pause, prev/next ayah), lets the user pick a reciter, and downloads
/// the surah for offline listening.
class PlayerBar extends ConsumerStatefulWidget {
  const PlayerBar({super.key, required this.surah, required this.ayahCount});
  final int surah;
  final int ayahCount;

  @override
  ConsumerState<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends ConsumerState<PlayerBar> {
  String? _effectiveReciter(ReciterCatalog catalog) =>
      ref.read(selectedReciterProvider) ?? catalog.defaultId;

  void _ensureLoaded(ReciterCatalog catalog) {
    final reciterId = _effectiveReciter(catalog);
    if (reciterId == null) return;
    // Defer so we don't mutate providers during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(audioControllerProvider.notifier)
          .ensureLoaded(widget.surah, widget.ayahCount, reciterId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(recitersProvider);
    final audio = ref.watch(audioControllerProvider);
    final theme = Theme.of(context);

    return catalogAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Material(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text('Audio unavailable: $e',
              style: TextStyle(color: theme.colorScheme.onErrorContainer)),
        ),
      ),
      data: (catalog) {
        _ensureLoaded(catalog);
        final reciter = catalog.byId(_effectiveReciter(catalog) ?? '');
        final lang = ref.watch(languageProvider);
        final controller = ref.read(audioControllerProvider.notifier);

        final dark = theme.brightness == Brightness.dark;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface
                .withValues(alpha: dark ? 0.62 : 0.72),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(
              top: BorderSide(
                  color: Colors.white.withValues(alpha: dark ? 0.12 : 0.5)),
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary
                    .withValues(alpha: dark ? 0.18 : 0.10),
                blurRadius: 28,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (audio.downloading) _downloadProgress(audio, theme),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      // Reciter selector.
                      Expanded(
                        child: TextButton.icon(
                          icon: const Icon(Icons.record_voice_over_outlined),
                          label: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              reciter?.localizedName(lang) ?? 'Select reciter',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          onPressed: () => _pickReciter(context, catalog, lang),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Previous ayah',
                        icon: const Icon(Icons.skip_previous),
                        onPressed: audio.hasPrev ? controller.prev : null,
                      ),
                      _playButton(audio, controller, theme),
                      IconButton(
                        tooltip: 'Next ayah',
                        icon: const Icon(Icons.skip_next),
                        onPressed: audio.hasNext ? controller.next : null,
                      ),
                      _downloadButton(audio, controller, theme),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ),
          ),
          ),
        );
      },
    );
  }

  Widget _playButton(
      AudioState audio, AudioController controller, ThemeData theme) {
    if (audio.loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
            width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final label = audio.currentAyah == null
        ? 'Play surah'
        : (audio.playing ? 'Pause' : 'Resume');
    return IconButton.filled(
      tooltip: label,
      iconSize: 32,
      icon: Icon(audio.playing ? Icons.pause : Icons.play_arrow),
      onPressed: controller.toggleSurah,
    );
  }

  Widget _downloadButton(
      AudioState audio, AudioController controller, ThemeData theme) {
    if (audio.downloading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (audio.downloaded) {
      return IconButton(
        tooltip: 'Downloaded for offline',
        icon: Icon(Icons.download_done, color: theme.colorScheme.primary),
        onPressed: null,
      );
    }
    return IconButton(
      tooltip: 'Download surah for offline',
      icon: const Icon(Icons.download_outlined),
      onPressed: controller.downloadCurrentSurah,
    );
  }

  Widget _downloadProgress(AudioState audio, ThemeData theme) {
    final value = audio.downloadTotal == 0
        ? null
        : audio.downloadDone / audio.downloadTotal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(child: LinearProgressIndicator(value: value)),
          const SizedBox(width: 8),
          Text('${audio.downloadDone}/${audio.downloadTotal}',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  void _pickReciter(BuildContext context, ReciterCatalog catalog, String lang) {
    const order = ['shia', 'universal', 'sunni'];
    const labels = {
      'shia': 'Shia / Iranian',
      'universal': 'Classic (all traditions)',
      'sunni': 'Sunni',
    };
    final current = _effectiveReciter(catalog);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scrollController) {
          final tiles = <Widget>[];
          for (final tradition in order) {
            final group =
                catalog.reciters.where((r) => r.tradition == tradition).toList();
            if (group.isEmpty) continue;
            tiles.add(Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(labels[tradition]!,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: Theme.of(context).colorScheme.primary)),
            ));
            for (final r in group) {
              final selected = r.id == current;
              tiles.add(ListTile(
                leading: Icon(selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(r.localizedName(lang)),
                subtitle: Text('${r.style} · ${r.bitrateKbps} kbps'),
                selected: selected,
                onTap: () {
                  ref.read(selectedReciterProvider.notifier).state = r.id;
                  ref.read(audioControllerProvider.notifier).setReciter(r.id);
                  Navigator.of(context).pop();
                },
              ));
            }
          }
          return ListView(controller: scrollController, children: tiles);
        },
      ),
    );
  }
}
