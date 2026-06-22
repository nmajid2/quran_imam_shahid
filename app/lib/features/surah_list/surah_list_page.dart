import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/theme_controller.dart';
import '../../data/models/surah.dart';
import '../../widgets/app_card.dart';
import '../../widgets/galaxy_background.dart';
import '../reader/surah_reader_page.dart';
import '../settings/settings_page.dart';
import '../settings/theme_picker_sheet.dart';

class SurahListPage extends ConsumerStatefulWidget {
  const SurahListPage({super.key});

  @override
  ConsumerState<SurahListPage> createState() => _SurahListPageState();
}

class _SurahListPageState extends ConsumerState<SurahListPage> {
  String _query = '';
  bool _animateEntrance = true;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scroll = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      // Emit normalized journey progress (0..1) rather than the raw offset, so
      // the cosmic zoom is paced to the list length: top = Solar System,
      // bottom = deepest cosmos. (Raw offset over-ran the journey: the list is
      // far taller than the zoom range, leaving a dead, motionless tail.)
      final pos = _scrollController.position;
      final max = pos.maxScrollExtent;
      _scroll.value = max > 1 ? (pos.pixels / max).clamp(0.0, 1.0) : 0.0;
    });
    // Animate only the first load; stop before recycled items re-animate.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _animateEntrance = false);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _matches(SurahSummary s, String lang) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return s.localizedName(lang).toLowerCase().contains(q) ||
        s.nameTranslit.toLowerCase().contains(q) ||
        s.nameAr.contains(_query) ||
        '${s.number}' == q;
  }

  @override
  Widget build(BuildContext context) {
    final surahs = ref.watch(surahListProvider);
    final lang = ref.watch(languageProvider);
    // The galaxy is a dark hero scene — render this page's content in the
    // selected preset's DARK theme so text/cards read well over space.
    final darkTheme =
        AppTheme.build(presetById(ref.watch(presetIdProvider)), Brightness.dark);
    final cs = darkTheme.colorScheme;

    return Theme(
      data: darkTheme,
      child: GalaxyBackground(
        scroll: _scroll,
        child: Scaffold(
          backgroundColor: Colors.transparent,
        body: surahs.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(
            message: 'Could not reach the gateway.\n$e',
            onRetry: () => ref.invalidate(surahListProvider),
          ),
          data: (list) {
            final filtered = list.where((s) => _matches(s, lang)).toList();
            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 132,
                  backgroundColor: Colors.transparent,
                  flexibleSpace: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: FlexibleSpaceBar(
                        titlePadding: const EdgeInsetsDirectional.only(
                            start: 20, bottom: 16),
                        title: ShaderMask(
                          shaderCallback: (r) => LinearGradient(
                            colors: [cs.primary, cs.secondary],
                          ).createShader(r),
                          child: const Text('Quran Imam Shahid',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                  color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'Appearance',
                      icon: const Icon(Icons.palette_outlined),
                      onPressed: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => const ThemePickerSheet(),
                      ),
                    ),
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
                    IconButton(
                      tooltip: 'Settings',
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsPage()),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: _SearchField(
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final card = _SurahCard(surah: filtered[i], lang: lang);
                      if (!_animateEntrance) return card;
                      return card
                          .animate()
                          .fadeIn(
                              duration: 360.ms,
                              delay: (40 * (i.clamp(0, 9))).ms)
                          .slideY(begin: 0.12, curve: Curves.easeOutCubic);
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search surah…',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: cs.surfaceContainerLow.withValues(alpha: 0.7),
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

class _SurahCard extends StatelessWidget {
  const _SurahCard({required this.surah, required this.lang});
  final SurahSummary surah;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final place = switch (surah.revelationPlace) {
      'makkah' => 'Meccan',
      'madinah' => 'Medinan',
      _ => '',
    };
    return AppCard(
      translucent: true,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SurahReaderPage(number: surah.number)),
      ),
      child: Row(
        children: [
          Hero(
            tag: 'surah-badge-${surah.number}',
            child: Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cs.primary, cs.secondary],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.45),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text('${surah.number}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(surah.localizedName(lang),
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  [
                    surah.nameTranslit,
                    '${surah.ayahCount} ayat',
                    if (place.isNotEmpty) place,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(surah.nameAr,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: cs.secondary,
                  fontFamilyFallback: const ['Scheherazade New', 'Amiri'])),
        ],
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
