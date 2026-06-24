import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/reciter.dart';
import 'audio_controller.dart';
import 'audio_prefs.dart';
import 'download_progress.dart';

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
        // Read-the-translation toggle: shown only for languages that have a
        // human translation-audio source (fa/en); Dutch has none.
        final hasTranslation = catalog.translationFor(lang) != null;
        final playTranslation = ref.watch(playTranslationProvider);

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
                if (audio.downloading)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                    child: DownloadProgressView(
                      done: audio.downloadDone,
                      total: audio.downloadTotal,
                      translationPhase: audio.downloadingTranslation,
                      langCode: lang.toUpperCase(),
                    ),
                  ),
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
                      if (hasTranslation)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: _TranslateToggle(
                            active: playTranslation,
                            langCode: lang.toUpperCase(),
                            onTap: () => ref
                                .read(playTranslationProvider.notifier)
                                .state = !playTranslation,
                          ),
                        ),
                      IconButton(
                        tooltip: 'Previous ayah',
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: audio.hasPrev ? controller.prev : null,
                      ),
                      _playButton(audio, controller, theme),
                      IconButton(
                        tooltip: 'Next ayah',
                        icon: const Icon(Icons.skip_next_rounded),
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
    final playing = audio.playing;
    final label = audio.currentAyah == null
        ? 'Play surah'
        : (playing ? 'Pause' : 'Resume');
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: playing
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.45),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : const [],
      ),
      child: IconButton.filled(
        tooltip: label,
        iconSize: 32,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey(playing),
          ),
        ),
        onPressed: controller.toggleSurah,
      ),
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
    // Fully downloaded (Arabic + translation where applicable) → no button.
    if (audio.downloaded) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Download surah for offline',
      icon: const Icon(Icons.download_rounded),
      onPressed: controller.downloadCurrentSurah,
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

/// Animated, glassy "read translation aloud" toggle. Off: a quiet outlined pill;
/// on: a glowing gradient pill that gently pulses — matching the app's
/// futuristic galaxy styling. Shows the translation language code (FA / EN).
class _TranslateToggle extends StatefulWidget {
  const _TranslateToggle({
    required this.active,
    required this.langCode,
    required this.onTap,
  });
  final bool active;
  final String langCode;
  final VoidCallback onTap;

  @override
  State<_TranslateToggle> createState() => _TranslateToggleState();
}

class _TranslateToggleState extends State<_TranslateToggle>
    with TickerProviderStateMixin {
  // _appear: 0 = off, 1 = on (drives the whole look). _pulse: the breathing glow
  // while on. Everything is computed from these two — no implicit AnimatedContainer
  // chasing a moving target — so each activation reaches FULL brightness.
  late final AnimationController _appear;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _appear = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: widget.active ? 1 : 0,
    );
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1700))
      ..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _TranslateToggle old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      widget.active ? _appear.forward() : _appear.reverse();
    }
  }

  @override
  void dispose() {
    _appear.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: Listenable.merge([_appear, _pulse]),
      builder: (context, _) {
        final a = Curves.easeOut.transform(_appear.value); // 0..1 on-ness
        final p = _pulse.value; // 0..1 breathing (only matters while on)
        final content = Color.lerp(cs.onSurfaceVariant, cs.onPrimary, a)!;
        final glass = cs.surfaceContainerHighest.withValues(alpha: 0.22);
        return Transform.scale(
          scale: 1.0 + 0.025 * a * p,
          child: Container(
            decoration: BoxDecoration(
              // Glass when off → bright primary (with a white sheen) when on.
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(glass, Color.lerp(cs.primary, Colors.white, 0.30)!, a)!,
                  Color.lerp(glass, cs.primary, a)!,
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Color.lerp(
                  cs.outlineVariant.withValues(alpha: 0.6),
                  Colors.white.withValues(alpha: 0.55 + 0.25 * p),
                  a,
                )!,
                width: 1 + 0.4 * a,
              ),
              // Glow scales with on-ness; bright even at the pulse's trough.
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: a * (0.5 + 0.3 * p)),
                  blurRadius: a * (16 + 10 * p),
                  spreadRadius: a,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: widget.onTap,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.subtitles_rounded, size: 18, color: content),
                      const SizedBox(width: 6),
                      Text(
                        widget.langCode,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              a > 0.5 ? FontWeight.w800 : FontWeight.w700,
                          letterSpacing: 0.5,
                          color: content,
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
}
