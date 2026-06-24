import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'ask_session.dart';

/// Stores the user's "Ask the Quran" conversations on disk (a JSON file in the
/// app documents dir) so they survive restarts. Sessions are listed on the home
/// page; the user can open a new one or continue a previous one.
class AskSessionsController extends StateNotifier<List<AskSession>> {
  AskSessionsController() : super([]) {
    _load();
  }

  static const _fileName = 'ask_sessions.json';
  File? _file;

  Future<File> _resolveFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    return _file = File('${dir.path}/$_fileName');
  }

  Future<void> _load() async {
    try {
      final f = await _resolveFile();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return;
      final loaded = raw
          .map((e) => AskSession.fromJson(e as Map<String, dynamic>))
          .where((s) => s.turns.isNotEmpty) // drop never-used sessions
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (mounted) state = loaded;
    } catch (_) {
      // Corrupt/missing file → start empty; not worth surfacing.
    }
  }

  Future<void> _persist() async {
    try {
      final f = await _resolveFile();
      await f.writeAsString(
          jsonEncode([for (final s in state) s.toJson()]));
    } catch (_) {
      // Best-effort; an unwritable disk shouldn't crash the conversation.
    }
  }

  /// Create a fresh, empty session (kept in memory; only persisted once it has a
  /// turn). Optional [surah]/[ayah]/[ayahEnd] record where it came from (a
  /// surah-scoped ask or a per-ayah summary) for the history label.
  AskSession newSession({int? surah, int? ayah, int? ayahEnd}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return AskSession(
        id: 'sess_$now',
        createdAt: now,
        updatedAt: now,
        surah: surah,
        ayah: ayah,
        ayahEnd: ayahEnd);
  }

  /// Record a completed exchange on [session], inserting the session at the top
  /// of the list if it's new, and persist.
  void addTurn(AskSession session, AskTurn turn) {
    session.turns.add(turn);
    session.updatedAt = DateTime.now().millisecondsSinceEpoch;
    final rest = state.where((s) => s.id != session.id).toList();
    state = [session, ...rest]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _persist();
  }

  void deleteSession(String id) {
    state = state.where((s) => s.id != id).toList();
    _persist();
  }

  void clearAll() {
    state = [];
    _persist();
  }
}

final askSessionsProvider =
    StateNotifierProvider<AskSessionsController, List<AskSession>>(
        (_) => AskSessionsController());
