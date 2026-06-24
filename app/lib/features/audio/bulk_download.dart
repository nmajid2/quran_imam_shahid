import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'audio_controller.dart';

/// Progress of a "download all surahs" run. The surah list shows the overall
/// count + a Cancel button, and each card shows live progress for the surah
/// currently downloading (and a ✓ once it lands, via [completed]).
class BulkDownloadState {
  const BulkDownloadState({
    this.active = false,
    this.currentSurah,
    this.currentTranslation = false,
    this.currentDone = 0,
    this.currentTotal = 0,
    this.surahsDone = 0,
    this.surahsTotal = 0,
    this.completed = const {},
  });

  final bool active;
  final int? currentSurah; // surah being fetched right now
  final bool currentTranslation; // current phase: translation vs Quran audio
  final int currentDone; // files done within the current surah
  final int currentTotal; // files to fetch for the current surah
  final int surahsDone; // surahs finished so far
  final int surahsTotal; // total surahs to process
  final Set<int> completed; // surahs fully fetched this run (for live ✓)

  BulkDownloadState copyWith({
    bool? active,
    int? currentSurah,
    bool? currentTranslation,
    int? currentDone,
    int? currentTotal,
    int? surahsDone,
    int? surahsTotal,
    Set<int>? completed,
  }) {
    return BulkDownloadState(
      active: active ?? this.active,
      currentSurah: currentSurah ?? this.currentSurah,
      currentTranslation: currentTranslation ?? this.currentTranslation,
      currentDone: currentDone ?? this.currentDone,
      currentTotal: currentTotal ?? this.currentTotal,
      surahsDone: surahsDone ?? this.surahsDone,
      surahsTotal: surahsTotal ?? this.surahsTotal,
      completed: completed ?? this.completed,
    );
  }
}

class BulkDownloadController extends StateNotifier<BulkDownloadState> {
  BulkDownloadController(this._ref) : super(const BulkDownloadState());

  final Ref _ref;
  bool _cancel = false;

  void cancel() {
    _cancel = true;
    // Hide the in-progress UI immediately (the loop stops within one file);
    // keep `completed` so finished surahs keep their ✓ until the rescan lands.
    if (state.active) state = state.copyWith(active: false);
  }

  /// Download every surah's Arabic (for [reciterId]) and translation (for
  /// [lang], where one exists), one surah at a time, fetching only missing
  /// files. Safe to interrupt with [cancel].
  Future<void> start({required String reciterId, required String lang}) async {
    if (state.active) return;
    _cancel = false;
    final dm = _ref.read(downloadManagerProvider);
    final store = _ref.read(localContentProvider);
    await store.ensureLoaded();
    final surahs = store.listSurahs();
    final trOwner = translationDownloadOwner(lang);
    state = BulkDownloadState(active: true, surahsTotal: surahs.length);
    try {
      for (final s in surahs) {
        if (_cancel) break;
        try {
          final arUrls = store.surahAudioUrls(reciterId, s.number);
          final trUrls = store.surahTranslationAudioUrls(lang, s.number);
          final missingAr = await dm.missingAyat(reciterId, s.number, arUrls);
          final missingTr = trUrls.isEmpty
              ? const <int, String>{}
              : await dm.missingAyat(trOwner, s.number, trUrls);
          final total = missingAr.length + missingTr.length;
          state = state.copyWith(
            currentSurah: s.number,
            currentTranslation: missingAr.isEmpty,
            currentDone: 0,
            currentTotal: total,
          );
          if (missingAr.isNotEmpty) {
            await dm.downloadSurah(reciterId, s.number, missingAr,
                isCancelled: () => _cancel,
                onProgress: (done, _) {
                  if (!_cancel) {
                    state = state.copyWith(
                        currentDone: done, currentTotal: total);
                  }
                });
          }
          if (_cancel) break;
          if (missingTr.isNotEmpty) {
            final base = missingAr.length;
            state =
                state.copyWith(currentTranslation: true, currentDone: base);
            await dm.downloadSurah(trOwner, s.number, missingTr,
                isCancelled: () => _cancel,
                onProgress: (done, _) {
                  if (!_cancel) {
                    state = state.copyWith(
                        currentDone: base + done, currentTotal: total);
                  }
                });
          }
        } catch (_) {
          // Skip a surah that fails (e.g. a transient network error) and
          // continue with the rest rather than aborting the whole run.
        }
        if (_cancel) break;
        state = state.copyWith(
          surahsDone: state.surahsDone + 1,
          completed: {...state.completed, s.number},
        );
      }
    } finally {
      // Refresh the persistent on-disk status before clearing the run state, so
      // the cards' ✓ chips stay set without a flicker.
      _ref.invalidate(downloadStatusProvider);
      try {
        await _ref.read(downloadStatusProvider.future);
      } catch (_) {}
      state = const BulkDownloadState();
    }
  }
}

final bulkDownloadProvider =
    StateNotifierProvider<BulkDownloadController, BulkDownloadState>(
        (ref) => BulkDownloadController(ref));
