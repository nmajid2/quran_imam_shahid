import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_usage.dart';
import 'tts_controller.dart';

/// Per-part read-aloud player. Collapsed it's a "Listen" button; once this part
/// is the one loaded in the shared TTS player it expands to full controls:
/// play/pause, skip back/forward 10s, a scrubber, and volume.
class PartAudioPlayer extends ConsumerWidget {
  const PartAudioPlayer({super.key, required this.source, this.label = 'Listen'});

  /// The (Markdown) text of this answer part; read as clean prose.
  final String source;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plain = plainForSpeech(source);
    if (plain.isEmpty) return const SizedBox.shrink();
    final id = ttsIdFor(plain);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final v = ref.watch(ttsControllerProvider.select((s) => (
          active: s.currentId == id || s.loadingId == id,
          playing: s.currentId == id && s.playing,
          loading: s.loadingId == id,
          volume: s.volume,
          duration: s.currentId == id ? s.duration : Duration.zero,
        )));
    final ctrl = ref.read(ttsControllerProvider.notifier);
    final est = estimateTtsCost(plain,
        audioDuration: v.duration > Duration.zero ? v.duration : null);
    final costStyle =
        theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant);

    if (!v.active) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: () => ctrl.play(id, plain),
              icon: const Icon(Icons.volume_up_rounded, size: 18),
              label: Text(label),
              style: TextButton.styleFrom(
                foregroundColor: cs.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              ),
            ),
            Text('≈ ${formatCost(est.costUsd)} TTS', style: costStyle),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: v.playing ? 'Pause' : 'Play',
                visualDensity: VisualDensity.compact,
                icon: v.loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(v.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
                color: cs.primary,
                onPressed: v.loading ? null : ctrl.toggle,
              ),
              IconButton(
                tooltip: 'Back 10s',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.replay_10_rounded),
                color: cs.onSurfaceVariant,
                onPressed: () => ctrl.seekBy(-10),
              ),
              const Expanded(child: _Scrubber()),
              IconButton(
                tooltip: 'Forward 10s',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.forward_10_rounded),
                color: cs.onSurfaceVariant,
                onPressed: () => ctrl.seekBy(10),
              ),
            ],
          ),
          Row(
            children: [
              Icon(
                  v.volume == 0
                      ? Icons.volume_off_rounded
                      : (v.volume < 0.5
                          ? Icons.volume_down_rounded
                          : Icons.volume_up_rounded),
                  size: 18,
                  color: cs.onSurfaceVariant),
              Expanded(
                child: Slider(
                  value: v.volume,
                  onChanged: ctrl.setVolume,
                ),
              ),
              IconButton(
                tooltip: 'Stop',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.stop_rounded),
                color: cs.primary,
                onPressed: ctrl.stop,
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Text(
                'TTS ≈ ${formatCost(est.costUsd)} · '
                '${formatTokens(est.inputTokens)} text + '
                '${formatTokens(est.audioTokens)} audio tok'
                '${est.fromDuration ? '' : ' (est.)'}',
                style: costStyle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The seek bar + time labels; rebuilds on each position tick (only the active
/// part has one on screen).
class _Scrubber extends ConsumerWidget {
  const _Scrubber();

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = ref.watch(ttsControllerProvider
        .select((s) => (pos: s.position, dur: s.duration)));
    final ctrl = ref.read(ttsControllerProvider.notifier);
    final dur = p.dur.inMilliseconds <= 0 ? 1 : p.dur.inMilliseconds;
    final pos = p.pos.inMilliseconds.clamp(0, dur);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2.5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: pos.toDouble(),
            max: dur.toDouble(),
            onChanged: (v) => ctrl.seekTo(Duration(milliseconds: v.round())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(p.pos), style: theme.textTheme.labelSmall),
              Text(_fmt(p.dur), style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ],
    );
  }
}
