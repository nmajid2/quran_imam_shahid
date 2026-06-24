import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/surah.dart';
import '../../widgets/app_background.dart';
import 'highlighted_text.dart';

/// Full-text Quran search (in-surah, used by the reader). When [surah] is set
/// the search is scoped to that surah; otherwise it spans the whole Quran.
/// Matches Arabic + the active translation (word-AND, any order,
/// diacritic-insensitive), served on-device.
class QuranSearchPage extends ConsumerStatefulWidget {
  const QuranSearchPage({super.key, this.surah, this.initialQuery});
  final int? surah;

  /// Pre-filled query (e.g. from a voice/text command "find X in surah Y").
  final String? initialQuery;

  @override
  ConsumerState<QuranSearchPage> createState() => _QuranSearchPageState();
}

class _QuranSearchPageState extends ConsumerState<QuranSearchPage> {
  final TextEditingController _input = TextEditingController();
  Timer? _debounce;
  String _query = '';
  AyahSearchResponse? _response;
  bool _loading = false;
  Object? _error;
  int _seq = 0; // guards against out-of-order async responses

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery?.trim();
    if (q != null && q.isNotEmpty) {
      _input.text = q;
      WidgetsBinding.instance.addPostFrameCallback((_) => _run(q));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(v.trim()));
  }

  Future<void> _run(String q) async {
    if (q == _query && _response != null) return;
    _query = q;
    if (q.isEmpty) {
      setState(() {
        _response = null;
        _loading = false;
        _error = null;
      });
      return;
    }
    final mySeq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lang = ref.read(languageProvider);
      final store = ref.read(localContentProvider);
      await store.ensureLoaded();
      final res = store.search(q, lang, surah: widget.surah);
      if (!mounted || mySeq != _seq) return;
      setState(() {
        _response = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || mySeq != _seq) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final lang = ref.watch(languageProvider);
    final scoped = widget.surah != null;

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: TextField(
            controller: _input,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (v) => _run(v.trim()),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText:
                  scoped ? 'Search in this surah…' : 'Search the whole Quran…',
            ),
          ),
          actions: [
            if (_input.text.isNotEmpty)
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _input.clear();
                  _run('');
                  setState(() {});
                },
              ),
          ],
        ),
        body: _body(theme, cs, lang),
      ),
    );
  }

  Widget _body(ThemeData theme, ColorScheme cs, String lang) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Search failed.\n$_error', textAlign: TextAlign.center),
        ),
      );
    }
    final res = _response;
    if (res == null) {
      return _Hint(
        icon: Icons.search,
        text: widget.surah != null
            ? 'Find words or phrases in this surah.'
            : 'Find words or phrases across the whole Quran.\nArabic or ${_langLabel(lang)} — type without diacritics.',
      );
    }
    if (res.results.isEmpty) {
      return _Hint(icon: Icons.search_off, text: 'No ayat matched “$_query”.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            res.truncated
                ? 'Showing ${res.results.length} of ${res.total} matches'
                : '${res.total} match${res.total == 1 ? '' : 'es'}',
            style:
                theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: res.results.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) =>
                AyahResultCard(result: res.results[i], lang: lang, query: _query),
          ),
        ),
      ],
    );
  }

  String _langLabel(String lang) => switch (lang) {
        'fa' => 'Persian',
        'nl' => 'Dutch',
        _ => 'English',
      };
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: cs.outline),
            const SizedBox(height: 14),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
