import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/models/surah.dart';
import '../../widgets/app_background.dart';
import '../../widgets/app_card.dart';
import '../audio/audio_controller.dart';
import '../audio/player_bar.dart';
import '../lexicon/lexicon_sheet.dart';
import 'tafsir_sheet.dart';

class SurahReaderPage extends ConsumerStatefulWidget {
  const SurahReaderPage({super.key, required this.number});
  final int number;

  @override
  ConsumerState<SurahReaderPage> createState() => _SurahReaderPageState();
}

class _SurahReaderPageState extends ConsumerState<SurahReaderPage> {
  final Map<int, GlobalKey> _ayahKeys = {};
  int? _lastScrolledAyah;

  GlobalKey _keyFor(int ayah) => _ayahKeys.putIfAbsent(ayah, () => GlobalKey());

  /// Keep the ayah being recited in view during continuous playback.
  void _onAudio(AudioState? prev, AudioState next) {
    if (next.surah != widget.number) return;
    final ayah = next.currentAyah;
    if (ayah == null || ayah == _lastScrolledAyah) return;
    _lastScrolledAyah = ayah;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _ayahKeys[ayah]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.15,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AudioState>(audioControllerProvider, _onAudio);
    final surah = ref.watch(surahProvider(widget.number));
    final lang = ref.watch(languageProvider);
    final cs = Theme.of(context).colorScheme;

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          titleSpacing: 0,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: const SizedBox.expand(),
            ),
          ),
          title: Row(
            children: [
              Hero(
                tag: 'surah-badge-${widget.number}',
                child: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [cs.primary, cs.secondary]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.5),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text('${widget.number}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              surah.maybeWhen(
                data: (s) => Text(s.nameTranslit),
                orElse: () => Text('Surah ${widget.number}'),
              ),
            ],
          ),
        ),
        body: surah.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (s) => ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: s.ayat.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AyahTile(
                key: _keyFor(s.ayat[i].ayah),
                surah: s,
                ayah: s.ayat[i],
                lang: lang,
              ),
            ),
          ),
        ),
        bottomNavigationBar: surah.maybeWhen(
          data: (s) => PlayerBar(surah: s.number, ayahCount: s.ayat.length),
          orElse: () => null,
        ),
      ),
    );
  }
}

class _AyahTile extends ConsumerWidget {
  const _AyahTile(
      {super.key, required this.surah, required this.ayah, required this.lang});
  final Surah surah;
  final Ayah ayah;
  final String lang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioControllerProvider);
    final isCurrent =
        audio.surah == surah.number && audio.currentAyah == ayah.ayah;
    final cs = Theme.of(context).colorScheme;
    final playing = isCurrent && audio.playing;

    return AppCard(
      selected: isCurrent,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${surah.number}:${ayah.ayah}',
                    style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ),
              const Spacer(),
              _RoundIcon(
                icon: Icons.menu_book_outlined,
                tooltip: 'Tafsir',
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => TafsirSheet(
                      surah: surah.number, ayah: ayah.ayah, lang: lang),
                ),
              ),
              const SizedBox(width: 4),
              _RoundIcon(
                icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                tooltip: playing ? 'Pause' : 'Play ayah',
                filled: isCurrent,
                onTap: () {
                  final c = ref.read(audioControllerProvider.notifier);
                  isCurrent ? c.toggle() : c.playAyah(ayah.ayah);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          _TappableArabic(text: ayah.textAr, lang: lang),
          const SizedBox(height: 10),
          Directionality(
            textDirection: lang == 'fa' ? TextDirection.rtl : TextDirection.ltr,
            child: Text(
              ayah.translation(lang),
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon(
      {required this.icon,
      required this.onTap,
      this.tooltip,
      this.filled = false});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: filled ? cs.primary : cs.primary.withValues(alpha: 0.10),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon,
                size: 22, color: filled ? cs.onPrimary : cs.primary),
          ),
        ),
      ),
    );
  }
}

/// Arabic ayah text where each word is tappable to open its lexicon entry.
class _TappableArabic extends StatelessWidget {
  const _TappableArabic({required this.text, required this.lang});
  final String text;
  final String lang;

  static final _arabic = RegExp('[ء-ي]');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(
        spacing: 7,
        runSpacing: 4,
        children: tokens.map((tok) {
          if (!_arabic.hasMatch(tok)) {
            return Text(tok, style: AppTheme.arabic);
          }
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => LexiconSheet(word: tok, lang: lang),
            ),
            child: Text(tok,
                style: AppTheme.arabic.copyWith(color: cs.onSurface)),
          );
        }).toList(),
      ),
    );
  }
}
