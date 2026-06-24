import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local_content.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/theme_controller.dart';
import '../../data/models/surah.dart';
import '../../widgets/app_card.dart';
import '../../widgets/galaxy_background.dart';
import '../ai/ai_cost_pending.dart';
import '../ai/ai_input_bar.dart';
import '../ai/ai_usage.dart';
import '../ai/ask_quran_sheet.dart';
import '../ai/ask_session.dart';
import '../ai/ask_sessions_sheet.dart';
import '../audio/audio_controller.dart';
import '../audio/bulk_download.dart';
import '../audio/download_progress.dart';
import '../assistant/app_command.dart';
import '../assistant/command_dispatcher.dart';
import '../reader/surah_reader_page.dart';
import '../search/highlighted_text.dart';
import '../settings/ai_settings_controller.dart';
import '../settings/settings_page.dart';
import '../settings/theme_picker_sheet.dart';

class SurahListPage extends ConsumerStatefulWidget {
  const SurahListPage({super.key});

  @override
  ConsumerState<SurahListPage> createState() => _SurahListPageState();
}

class _SurahListPageState extends ConsumerState<SurahListPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = ''; // live surah-name filter text
  bool _animateEntrance = true;
  bool _routing = false; // an AI command is being classified
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scroll = ValueNotifier<double>(0);

  // Inline whole-Quran keyword results (shown when a search command resolves).
  String _kwQuery = '';
  AyahSearchResponse? _kwResponse;
  int _kwSeq = 0;

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
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _matches(SurahSummary s, String lang) {
    if (_query.trim().isEmpty) return true;
    final q = _query.toLowerCase().trim();
    return s.localizedName(lang).toLowerCase().contains(q) ||
        s.nameTranslit.toLowerCase().contains(q) ||
        s.nameAr.contains(_query.trim()) ||
        '${s.number}' == q;
  }

  /// Live, local: filter the surah list as the user types (no AI). Editing also
  /// dismisses any keyword results so the list is back.
  void _onChanged(String v) {
    setState(() {
      _query = v;
      if (_kwResponse != null) _kwResponse = null;
    });
  }

  /// On submit / voice: a bare surah name or number navigates locally (no AI);
  /// anything else goes to the command router, then the dispatcher executes it.
  Future<void> _onSubmit({bool fromVoice = false}) async {
    final text = _searchCtrl.text.trim();
    if (text.isEmpty || _routing) return;
    _searchFocus.unfocus();
    // Clear the box (and its live surah-name filter) now that the question /
    // command has been submitted. Programmatic clear() doesn't fire onChanged,
    // so reset _query explicitly.
    _searchCtrl.clear();
    setState(() => _query = '');

    final list = ref.read(surahListProvider).valueOrNull ?? const [];
    final lang = ref.read(languageProvider);
    final fast = _localSurahMatch(text, list, lang);
    if (fast != null) {
      _openSurah(fast.number);
      return;
    }

    setState(() => _routing = true);
    try {
      final routeUsage = <AiCallUsage>[];
      final json = await ref.read(openAiClientProvider).routeCommand(
            model: ref.read(classifyModelProvider),
            lang: lang,
            text: text,
            usage: routeUsage,
          );
      if (!mounted) return;
      final routed = RoutedCommand.fromJson(json);
      // Stash the router cost (+ any voice STT/refine) so the Ask sheet folds it
      // into the answer it produces. A non-"ask" command opens no answer turn,
      // so its routing cost is dropped instead of carried to a later question.
      final pending = ref.read(pendingAiCostProvider.notifier);
      pending.addChat(routeUsage);
      await CommandDispatcher(context, ref)
          .run(routed, onInlineSearch: _showKeyword, fromVoice: fromVoice);
      if (routed.command is! AskCommand) pending.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Could not understand: $e')));
      }
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  /// Conservative fast-path: a bare surah number (1–114) or an exact name match.
  SurahSummary? _localSurahMatch(
      String text, List<SurahSummary> list, String lang) {
    if (list.isEmpty) return null;
    final n = int.tryParse(text);
    if (n != null && n >= 1 && n <= 114) {
      return list.firstWhere((s) => s.number == n);
    }
    final q = text.toLowerCase();
    final qa = normalizeArabicForSearch(text);
    for (final s in list) {
      if (s.nameTranslit.toLowerCase() == q ||
          s.localizedName(lang).toLowerCase() == q ||
          normalizeArabicForSearch(s.nameAr) == qa) {
        return s;
      }
    }
    return null;
  }

  void _openSurah(int number) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SurahReaderPage(number: number)),
    );
  }

  /// Confirm, then download every surah (Arabic + translation) one by one.
  Future<void> _downloadAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download all surahs?'),
        content: const Text(
            'This downloads every surah — Arabic recitation plus the translation '
            'for your language where one exists — for offline use. It may take a '
            'while and use significant data and storage.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Download')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final lang = ref.read(languageProvider);
    final catalog = await ref.read(recitersProvider.future);
    final reciterId = ref.read(selectedReciterProvider) ?? catalog.defaultId;
    await ref
        .read(bulkDownloadProvider.notifier)
        .start(reciterId: reciterId, lang: lang);
  }

  /// Inline whole-Quran keyword search (called by the dispatcher's search intent).
  Future<void> _showKeyword(String q) async {
    final query = q.trim();
    if (query.isEmpty) return;
    final mySeq = ++_kwSeq;
    final lang = ref.read(languageProvider);
    final store = ref.read(localContentProvider);
    await store.ensureLoaded();
    final res = store.search(query, lang);
    if (!mounted || mySeq != _kwSeq) return;
    setState(() {
      _kwQuery = query;
      _kwResponse = res;
    });
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
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final session = await showModalBottomSheet<AskSession>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const AskSessionsSheet(),
            );
            if (session == null || !context.mounted) return;
            await showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => AskQuranSheet(
                  session: session, lang: lang, surah: session.surah),
            );
          },
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Ask AI'),
        ),
        body: surahs.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(
            message: 'Could not load the Quran data.\n$e',
            onRetry: () => ref.invalidate(surahListProvider),
          ),
          data: (list) {
            final filtered = list.where((s) => _matches(s, lang)).toList();
            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: Colors.transparent,
                  toolbarHeight: 64,
                  titleSpacing: 16,
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _AppEmblem(),
                      const SizedBox(width: 10),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: _ShimmerTitle(
                            text: 'Quran Imam Shahid',
                            color: Color.lerp(Colors.white, cs.primary, 0.16)!,
                          ),
                        ),
                      ),
                    ],
                  ),
                  flexibleSpace: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              cs.surface.withValues(alpha: 0.32),
                              cs.surface.withValues(alpha: 0.06),
                            ],
                          ),
                          border: Border(
                            bottom: BorderSide(
                                color: cs.primary.withValues(alpha: 0.28)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    _DownloadAllAction(onStart: _downloadAll),
                    _GlassIconButton(
                      icon: Icons.color_lens_rounded,
                      tooltip: 'Appearance',
                      onTap: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => const ThemePickerSheet(),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Language',
                      padding: EdgeInsets.zero,
                      offset: const Offset(0, 48),
                      onSelected: (l) =>
                          ref.read(languageProvider.notifier).state = l,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'fa', child: Text('فارسی')),
                        PopupMenuItem(value: 'en', child: Text('English')),
                        PopupMenuItem(value: 'nl', child: Text('Nederlands')),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2),
                        child: _GlassChip(icon: Icons.language_rounded),
                      ),
                    ),
                    _GlassIconButton(
                      icon: Icons.settings_rounded,
                      tooltip: 'Settings',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsPage()),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: AiInputBar(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      enabled: !_routing,
                      hint: _boxHint(lang),
                      isRtl: lang == 'fa',
                      lang: lang,
                      sheetStyle: false,
                      onChanged: _onChanged,
                      onSubmit: _onSubmit,
                    ),
                  ),
                ),
                if (ref.watch(bulkDownloadProvider.select((s) => s.active)))
                  const SliverToBoxAdapter(child: _BulkBanner()),
                if (_routing)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (_kwResponse != null)
                  ..._keywordSlivers(lang)
                else
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

  /// Inline keyword results (after a "search …" command resolves).
  List<Widget> _keywordSlivers(String lang) {
    final res = _kwResponse!;
    if (res.results.isEmpty) {
      return [_kwHint(Icons.search_off, 'No ayat matched “$_kwQuery”.')];
    }
    final cs = Theme.of(context).colorScheme;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  res.truncated
                      ? 'Showing ${res.results.length} of ${res.total} for “$_kwQuery”'
                      : '${res.total} match${res.total == 1 ? '' : 'es'} for “$_kwQuery”',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _kwResponse = null;
                  _searchCtrl.clear();
                  _query = '';
                }),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Clear'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        sliver: SliverList.separated(
          itemCount: res.results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final card =
                AyahResultCard(result: res.results[i], lang: lang, query: _kwQuery);
            return card
                .animate(key: ValueKey('${_kwQuery}_$i'))
                .fadeIn(duration: 300.ms, delay: (30 * (i.clamp(0, 8))).ms)
                .slideY(begin: 0.1, curve: Curves.easeOutCubic);
          },
        ),
      ),
    ];
  }

  Widget _kwHint(IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
        child: Column(
          children: [
            Icon(icon, size: 42, color: cs.outline),
            const SizedBox(height: 14),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.5)),
          ],
        ),
      ),
    );
  }

  String _boxHint(String lang) => switch (lang) {
        'fa' => 'جستجو، یا بپرسید/فرمان دهید…',
        'nl' => 'Zoek, of vraag / geef een opdracht…',
        _ => 'Search, or ask / command…',
      };
}

class _SurahCard extends ConsumerWidget {
  const _SurahCard({required this.surah, required this.lang});
  final SurahSummary surah;
  final String lang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final place = switch (surah.revelationPlace) {
      'makkah' => 'Meccan',
      'madinah' => 'Medinan',
      _ => '',
    };
    // A download started from this surah's reader keeps running globally, so the
    // card shows its live progress even after the user backs out. Selected so
    // only this card rebuilds on each tick (other cards see a steady null).
    // Live download progress for this surah — from a single-surah download (the
    // reader's button) or the "download all" run; same shape so either drives
    // the same indicator.
    final single = ref.watch(audioControllerProvider.select((s) =>
        (s.downloading && s.surah == surah.number)
            ? (
                done: s.downloadDone,
                total: s.downloadTotal,
                tr: s.downloadingTranslation
              )
            : null));
    final bulk = ref.watch(bulkDownloadProvider.select((s) =>
        (s.active && s.currentSurah == surah.number)
            ? (
                done: s.currentDone,
                total: s.currentTotal,
                tr: s.currentTranslation
              )
            : null));
    final dl = single ?? bulk;
    // Per-surah offline status: Arabic for the active reciter, translation for
    // the current language. From the filesystem scan, refreshed after downloads.
    final catalog = ref.watch(recitersProvider).valueOrNull;
    final status = ref.watch(downloadStatusProvider).valueOrNull;
    final reciterId = ref.watch(selectedReciterProvider) ?? catalog?.defaultId;
    final hasTr = catalog?.translationFor(lang) != null;
    // A surah finished during the current "download all" run shows ✓ live,
    // without waiting for the next filesystem rescan.
    final bulkDone = ref.watch(
        bulkDownloadProvider.select((s) => s.completed.contains(surah.number)));
    final arabicDone = bulkDone ||
        (status != null &&
            reciterId != null &&
            status.isComplete(reciterId, surah.number, surah.ayahCount));
    final trDone = hasTr &&
        (bulkDone ||
            (status != null &&
                status.isComplete(
                    translationDownloadOwner(lang), surah.number, surah.ayahCount)));
    return AppCard(
      translucent: true,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SurahReaderPage(number: surah.number)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
          if (dl != null) ...[
            const SizedBox(height: 12),
            DownloadProgressView(
              done: dl.done,
              total: dl.total,
              translationPhase: dl.tr,
              langCode: lang.toUpperCase(),
            ),
          ] else if (status != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _DownloadStatusChips(
                arabicDownloaded: arabicDone,
                hasTranslation: hasTr,
                translationDownloaded: trDone,
                langCode: lang.toUpperCase(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Two small offline-status chips on a surah card — Quran (Arabic) and, when the
/// language has a translation source, the translation. Bright with a check when
/// downloaded; faint and outlined when not. Animates as status changes.
class _DownloadStatusChips extends StatelessWidget {
  const _DownloadStatusChips({
    required this.arabicDownloaded,
    required this.hasTranslation,
    required this.translationDownloaded,
    required this.langCode,
  });
  final bool arabicDownloaded;
  final bool hasTranslation;
  final bool translationDownloaded;
  final String langCode;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusChip(
          icon: Icons.headphones_rounded,
          label: 'Quran',
          downloaded: arabicDownloaded,
        ),
        if (hasTranslation) ...[
          const SizedBox(width: 6),
          _StatusChip(
            icon: Icons.record_voice_over_rounded,
            label: langCode,
            downloaded: translationDownloaded,
          ),
        ],
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.downloaded,
  });
  final IconData icon;
  final String label;
  final bool downloaded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = downloaded
        ? cs.primary
        : cs.onSurfaceVariant.withValues(alpha: 0.55);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: downloaded
            ? cs.primary.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: downloaded
              ? cs.primary.withValues(alpha: 0.45)
              : cs.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: downloaded
            ? [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.22),
                  blurRadius: 8,
                  spreadRadius: -1,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Persistent audio glyph so the tag clearly reads as audio.
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.0,
              fontWeight: downloaded ? FontWeight.w700 : FontWeight.w500,
              color: fg,
            ),
          ),
          // A check appears once it's downloaded.
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: downloaded
                ? Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.check_circle_rounded,
                        size: 12, color: cs.primary),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// The app's gradient emblem in the header.
class _AppEmblem extends StatelessWidget {
  const _AppEmblem();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, cs.secondary],
        ),
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.45),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Icon(Icons.menu_book_rounded, size: 16, color: Colors.white),
    );
  }
}

/// The title in a refined platinum tone with a single soft sheen that glides
/// across every few seconds, then rests — understated and prestigious.
class _ShimmerTitle extends StatefulWidget {
  const _ShimmerTitle({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  State<_ShimmerTitle> createState() => _ShimmerTitleState();
}

class _ShimmerTitleState extends State<_ShimmerTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4800))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) {
            // One narrow highlight sweeps over the platinum base during the
            // first ~38% of the cycle, then the title rests evenly lit.
            final sweep = (_c.value / 0.38).clamp(0.0, 1.0);
            final c = sweep * 1.5 - 0.25; // -0.25 → 1.25
            double cl(double v) => v.clamp(0.0, 1.0);
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [widget.color, Colors.white, widget.color],
              stops: [cl(c - 0.16), cl(c), cl(c + 0.16)],
            ).createShader(rect);
          },
          child: Text(
            widget.text,
            maxLines: 1,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16.5,
                letterSpacing: 0.6,
                color: Colors.white),
          ),
        );
      },
    );
  }
}

/// A glassy circular chip (translucent gradient + hairline border) used for the
/// header action buttons; [highlight] tints it with the accent + a glow.
class _GlassChip extends StatelessWidget {
  const _GlassChip({this.icon, this.child, this.highlight = false});
  final IconData? icon;
  final Widget? child;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: highlight
              ? [
                  cs.primary.withValues(alpha: 0.32),
                  cs.primary.withValues(alpha: 0.14),
                ]
              : [
                  cs.surface.withValues(alpha: 0.5),
                  cs.surfaceContainerHighest.withValues(alpha: 0.22),
                ],
        ),
        border: Border.all(
          color: highlight
              ? cs.primary.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.14),
        ),
        boxShadow: highlight
            ? [
                BoxShadow(
                    color: cs.primary.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: -1),
              ]
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 6,
                    offset: const Offset(0, 2)),
              ],
      ),
      child: child ??
          Icon(icon, size: 18, color: cs.onSurface.withValues(alpha: 0.92)),
    );
  }
}

/// A tappable [_GlassChip] with a press-scale animation, for header actions.
class _GlassIconButton extends StatefulWidget {
  const _GlassIconButton(
      {this.icon, this.child, this.tooltip, this.onTap, this.highlight = false});
  final IconData? icon;
  final Widget? child;
  final String? tooltip;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  State<_GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<_GlassIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    Widget w = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.86 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: _GlassChip(
            icon: widget.icon, highlight: widget.highlight, child: widget.child),
      ),
    );
    w = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: w);
    return widget.tooltip != null
        ? Tooltip(message: widget.tooltip!, child: w)
        : w;
  }
}

/// Header action that starts the "download all" run, then turns into a always-
/// reachable Stop button with an overall-progress ring while it's running.
class _DownloadAllAction extends ConsumerWidget {
  const _DownloadAllAction({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final s = ref.watch(bulkDownloadProvider);
    if (!s.active) {
      return _GlassIconButton(
        icon: Icons.download_for_offline_rounded,
        tooltip: 'Download all surahs',
        onTap: onStart,
      );
    }
    final frac = s.surahsTotal == 0 ? null : s.surahsDone / s.surahsTotal;
    return _GlassIconButton(
      tooltip: 'Stop downloading',
      highlight: true,
      onTap: () => ref.read(bulkDownloadProvider.notifier).cancel(),
      child: SizedBox(
        width: 23,
        height: 23,
        child: Stack(
          alignment: Alignment.center,
          children: [
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              tween: Tween(begin: 0, end: frac ?? 0),
              builder: (context, v, _) => CircularProgressIndicator(
                value: frac == null ? null : v,
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation(cs.primary),
                backgroundColor: cs.onSurface.withValues(alpha: 0.15),
              ),
            ),
            Icon(Icons.stop_rounded, size: 12, color: cs.primary),
          ],
        ),
      ),
    );
  }
}

/// Overall "download all" progress + a Cancel button, shown under the search box
/// while a bulk download runs. Per-surah detail appears on each card.
class _BulkBanner extends ConsumerWidget {
  const _BulkBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final b = ref.watch(bulkDownloadProvider);
    final value = b.surahsTotal == 0 ? null : b.surahsDone / b.surahsTotal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.download_for_offline_rounded,
                color: cs.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Downloading all surahs · ${b.surahsDone}/${b.surahsTotal}',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      tween: Tween(begin: 0, end: value ?? 0),
                      builder: (context, v, _) => LinearProgressIndicator(
                        value: value == null ? null : v,
                        minHeight: 6,
                        backgroundColor:
                            cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        valueColor: AlwaysStoppedAnimation(cs.primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => ref.read(bulkDownloadProvider.notifier).cancel(),
              child: const Text('Cancel'),
            ),
          ],
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
