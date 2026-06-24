import 'package:flutter/material.dart';

/// Animated download indicator: names the current phase — Quran (Arabic) audio
/// first, then the translation — with a pulsing accent, a soft cross-fade when
/// the phase switches, and a smooth-filling rounded bar. Renders with no outer
/// padding so callers can place it anywhere (the player bar and the surah-list
/// card both use it).
class DownloadProgressView extends StatefulWidget {
  const DownloadProgressView({
    super.key,
    required this.done,
    required this.total,
    required this.translationPhase,
    required this.langCode,
  });

  final int done;
  final int total;
  final bool translationPhase; // false = Quran audio, true = translation
  final String langCode; // e.g. FA / EN

  @override
  State<DownloadProgressView> createState() => _DownloadProgressViewState();
}

class _DownloadProgressViewState extends State<DownloadProgressView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tr = widget.translationPhase;
    final value = widget.total == 0 ? null : widget.done / widget.total;
    final label = tr ? 'translation · ${widget.langCode}' : 'Quran audio';
    final icon = tr ? Icons.subtitles_rounded : Icons.menu_book_rounded;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position:
                        Tween(begin: const Offset(0, 0.35), end: Offset.zero)
                            .animate(anim),
                    child: child,
                  ),
                ),
                child: Row(
                  key: ValueKey(tr),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: Tween(begin: 0.45, end: 1.0).animate(_pulse),
                      child: Icon(icon, size: 16, color: cs.primary),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Downloading $label',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${widget.done}/${widget.total}',
              style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            tween: Tween(begin: 0, end: value ?? 0),
            builder: (context, v, _) => LinearProgressIndicator(
              value: value == null ? null : v,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              valueColor: AlwaysStoppedAnimation(cs.primary),
            ),
          ),
        ),
      ],
    );
  }
}
