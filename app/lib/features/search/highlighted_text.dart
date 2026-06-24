import 'package:flutter/material.dart';

import '../../core/local_content.dart';
import '../../data/models/surah.dart';
import '../../widgets/app_card.dart';
import '../reader/surah_reader_page.dart';

/// Renders [text] with the words that match any of [tokens] accented and gently
/// pulsing with a soft glow — a futuristic "here it is" cue. Whole matched words
/// are highlighted; [arabicFold] selects diacritic-folding vs. lowercasing so it
/// lines up with the (offline) search matcher.
class HighlightedText extends StatefulWidget {
  const HighlightedText({
    super.key,
    required this.text,
    required this.tokens,
    required this.base,
    required this.arabicFold,
    required this.rtl,
  });
  final String text;
  final List<String> tokens;
  final TextStyle base;
  final bool arabicFold;
  final bool rtl;

  @override
  State<HighlightedText> createState() => _HighlightedTextState();
}

class _HighlightedTextState extends State<HighlightedText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late List<_Word> _words;
  bool _hasMatch = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _segment();
    if (_hasMatch) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant HighlightedText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || !_sameTokens(old.tokens, widget.tokens)) {
      _segment();
      if (_hasMatch) {
        if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
      } else {
        _pulse.stop();
      }
    }
  }

  bool _sameTokens(List<String> a, List<String> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((x) => x);

  String _norm(String s) =>
      widget.arabicFold ? normalizeArabicForSearch(s) : s.toLowerCase();

  void _segment() {
    // Split into word runs while PRESERVING the whitespace between them — Dart's
    // String.split drops delimiters (even captured ones), which would mash the
    // ayah into one unreadable run.
    final text = widget.text;
    final words = <_Word>[];
    var last = 0;
    for (final m in RegExp(r'\S+').allMatches(text)) {
      if (m.start > last) words.add(_Word(text.substring(last, m.start), false));
      final w = m.group(0)!;
      words.add(_Word(w, _matches(w, widget.tokens)));
      last = m.end;
    }
    if (last < text.length) words.add(_Word(text.substring(last), false));
    _words = words;
    _hasMatch = _words.any((w) => w.match);
  }

  bool _matches(String word, List<String> tokens) {
    if (tokens.isEmpty) return false;
    final n = _norm(word);
    if (n.isEmpty) return false;
    return tokens.any((t) => n.contains(t));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    if (!_hasMatch) {
      return Directionality(
        textDirection: widget.rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Text(widget.text, style: widget.base),
      );
    }
    return Directionality(
      textDirection: widget.rtl ? TextDirection.rtl : TextDirection.ltr,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_pulse.value);
          final hl = widget.base.copyWith(
            color: accent,
            fontWeight: FontWeight.w700,
            shadows: [
              Shadow(
                color: accent.withValues(alpha: 0.35 + 0.45 * t),
                blurRadius: 6 + 12 * t,
              ),
            ],
          );
          return Text.rich(
            TextSpan(
              children: [
                for (final w in _words)
                  TextSpan(text: w.text, style: w.match ? hl : widget.base),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Word {
  _Word(this.text, this.match);
  final String text;
  final bool match;
}

/// A search-result card: the ayah ref, Arabic, and translation with matched
/// words highlighted. Tapping opens the reader at that ayah.
class AyahResultCard extends StatelessWidget {
  const AyahResultCard(
      {super.key,
      required this.result,
      required this.lang,
      required this.query});
  final AyahSearchResult result;
  final String lang;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final words =
        query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final arTokens = [
      for (final w in words)
        if (normalizeArabicForSearch(w).isNotEmpty)
          normalizeArabicForSearch(w)
    ];
    final trTokens =
        lang == 'fa' ? arTokens : [for (final w in words) w.toLowerCase()];

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              SurahReaderPage(number: result.surah, initialAyah: result.ayah),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${result.surah}:${result.ayah}',
                style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ),
          const SizedBox(height: 10),
          HighlightedText(
            text: result.textAr,
            tokens: arTokens,
            arabicFold: true,
            rtl: true,
            base: const TextStyle(
                fontSize: 20,
                height: 1.8,
                fontFamilyFallback: ['Scheherazade New', 'Amiri']),
          ),
          if (result.translation.isNotEmpty) ...[
            const SizedBox(height: 8),
            HighlightedText(
              text: result.translation,
              tokens: trTokens,
              arabicFold: lang == 'fa',
              rtl: lang == 'fa',
              base: theme.textTheme.bodyMedium!
                  .copyWith(color: cs.onSurfaceVariant, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}
