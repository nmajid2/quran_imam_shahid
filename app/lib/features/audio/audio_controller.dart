import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/providers.dart';
import '../../data/models/reciter.dart';
import 'audio_prefs.dart';
import 'download_manager.dart';

/// Which clip is currently playing for the active ayah: the Arabic recitation,
/// or (when "read translation" is on) that ayah's translation audio after it.
enum _Leg { arabic, translation }

final downloadManagerProvider =
    Provider<DownloadManager>((ref) => DownloadManager());

/// Storage "owner" key for a language's translation audio on disk — keeps it
/// separate from the Arabic reciters. Shared by the downloader and the UI.
String translationDownloadOwner(String lang) => 'translation_$lang';

/// Snapshot of how many ayah files are on disk per owner + surah, for badging
/// surah cards with their offline status. Refreshed after each download.
class DownloadStatus {
  const DownloadStatus(this._counts);
  final Map<String, Map<int, int>> _counts;

  bool isComplete(String owner, int surah, int ayahCount) =>
      ayahCount > 0 && (_counts[owner]?[surah] ?? 0) >= ayahCount;
}

final downloadStatusProvider = FutureProvider<DownloadStatus>((ref) async {
  final dm = ref.watch(downloadManagerProvider);
  return DownloadStatus(await dm.scanCounts());
});

/// Reciter catalog — bundled in the APK, read on-device (no gateway).
final recitersProvider = FutureProvider<ReciterCatalog>((ref) async {
  final store = ref.watch(localContentProvider);
  await store.ensureLoaded();
  return store.reciters();
});

/// The reciter the user has chosen. Null until first set; the UI falls back to
/// the catalog's default. Persists across surahs for the session.
final selectedReciterProvider = StateProvider<String?>((ref) => null);

/// Immutable snapshot of what the player is doing, for the bottom bar.
class AudioState {
  final int? surah;
  final int? currentAyah;
  final int ayahCount;
  final String? reciterId;
  final bool playing;
  final bool continuous; // full-surah mode: advance on completion
  final bool loading; // preparing/buffering the current ayah
  final bool downloading;
  final int downloadDone;
  final int downloadTotal;
  final bool downloadingTranslation; // current phase: translation vs Quran audio
  final bool downloaded; // whole surah present on disk for this reciter
  final String? error;

  const AudioState({
    this.surah,
    this.currentAyah,
    this.ayahCount = 0,
    this.reciterId,
    this.playing = false,
    this.continuous = false,
    this.loading = false,
    this.downloading = false,
    this.downloadDone = 0,
    this.downloadTotal = 0,
    this.downloadingTranslation = false,
    this.downloaded = false,
    this.error,
  });

  bool get hasNext => currentAyah != null && currentAyah! < ayahCount;
  bool get hasPrev => currentAyah != null && currentAyah! > 1;

  AudioState copyWith({
    int? surah,
    int? currentAyah,
    int? ayahCount,
    String? reciterId,
    bool? playing,
    bool? continuous,
    bool? loading,
    bool? downloading,
    int? downloadDone,
    int? downloadTotal,
    bool? downloadingTranslation,
    bool? downloaded,
    String? error,
    bool clearError = false,
  }) {
    return AudioState(
      surah: surah ?? this.surah,
      currentAyah: currentAyah ?? this.currentAyah,
      ayahCount: ayahCount ?? this.ayahCount,
      reciterId: reciterId ?? this.reciterId,
      playing: playing ?? this.playing,
      continuous: continuous ?? this.continuous,
      loading: loading ?? this.loading,
      downloading: downloading ?? this.downloading,
      downloadDone: downloadDone ?? this.downloadDone,
      downloadTotal: downloadTotal ?? this.downloadTotal,
      downloadingTranslation:
          downloadingTranslation ?? this.downloadingTranslation,
      downloaded: downloaded ?? this.downloaded,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AudioController extends StateNotifier<AudioState> {
  AudioController(this._ref) : super(const AudioState()) {
    _player = AudioPlayer();
    _stateSub = _player.playerStateStream.listen(_onPlayerState);
  }

  final Ref _ref;
  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _stateSub;

  Map<int, String> _urls = {}; // ayah -> CDN url for the loaded surah/reciter
  bool _advancing = false;
  _Leg _leg = _Leg.arabic; // current ayah's clip: Arabic, then optional translation

  DownloadManager get _downloads => _ref.read(downloadManagerProvider);

  /// Load a surah for a reciter (no-op if already loaded for that pair).
  Future<void> ensureLoaded(int surah, int ayahCount, String reciterId) async {
    if (state.surah == surah && state.reciterId == reciterId) return;
    await _loadSurah(surah, ayahCount, reciterId);
  }

  Future<void> _loadSurah(int surah, int ayahCount, String reciterId) async {
    await _player.stop();
    state = AudioState(
      surah: surah,
      ayahCount: ayahCount,
      reciterId: reciterId,
      loading: true,
    );
    try {
      final store = _ref.read(localContentProvider);
      await store.ensureLoaded();
      _urls = store.surahAudioUrls(reciterId, surah);
      final downloaded = await _computeDownloaded(surah, reciterId, ayahCount);
      state = state.copyWith(loading: false, downloaded: downloaded);
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  /// Switch reciter, reloading the current surah's sources.
  Future<void> setReciter(String reciterId) async {
    final surah = state.surah;
    if (surah == null) {
      state = state.copyWith(reciterId: reciterId);
      return;
    }
    final wasPlaying = state.playing;
    final ayah = state.currentAyah;
    final continuous = state.continuous;
    await _loadSurah(surah, state.ayahCount, reciterId);
    if (wasPlaying && ayah != null) {
      await playAyah(ayah, continuous: continuous);
    }
  }

  /// Resolve the best source for an ayah: local file if downloaded, else CDN.
  Future<Uri?> _sourceFor(int surah, int ayah, String reciterId) async {
    final local = await _downloads.localPath(reciterId, surah, ayah);
    if (local != null) return Uri.file(local);
    final url = _urls[ayah];
    return url == null ? null : Uri.parse(url);
  }

  /// Play a single ayah. [continuous] keeps playing the rest of the surah.
  Future<void> playAyah(int ayah, {bool continuous = false}) async {
    final surah = state.surah;
    final reciterId = state.reciterId;
    if (surah == null || reciterId == null) return;
    _leg = _Leg.arabic; // a new ayah always starts with its Arabic recitation
    final uri = await _sourceFor(surah, ayah, reciterId);
    if (uri == null) {
      state = state.copyWith(error: 'No audio for ayah $ayah');
      return;
    }
    state = state.copyWith(
      currentAyah: ayah,
      continuous: continuous,
      loading: true,
      clearError: true,
    );
    try {
      await _player.setAudioSource(AudioSource.uri(uri));
      state = state.copyWith(loading: false, playing: true);
      await _player.play();
    } catch (e) {
      state = state.copyWith(loading: false, playing: false, error: '$e');
    }
  }

  /// Play the whole surah from ayah 1 (or resume from the current ayah).
  Future<void> playSurah() async {
    final start = state.currentAyah ?? 1;
    await playAyah(start, continuous: true);
  }

  /// Select an ayah as THE active one — the card highlight, the AI summary target,
  /// and the start point for the bottom play button — without auto-playing. This is
  /// the single source of truth, so tapping a card and tapping a card's play button
  /// can never produce two different "selected" cards. Stops any current playback so
  /// the highlight always matches the player.
  Future<void> select(int ayah) async {
    if (state.currentAyah == ayah) return; // already active — don't interrupt
    await _player.stop();
    _leg = _Leg.arabic;
    state = state.copyWith(currentAyah: ayah, continuous: false, playing: false);
  }

  /// The bottom bar's main button: a surah-level play/pause. Unlike [toggle]
  /// (which preserves single-ayah mode), this always continues the surah from
  /// the current position — so pressing it after a single card ayah keeps
  /// playing onward rather than stopping at that one ayah.
  Future<void> toggleSurah() async {
    if (_player.playing) {
      await _player.pause();
      state = state.copyWith(playing: false);
      return;
    }
    // Resume a live (paused) ayah, now continuing the whole surah; otherwise
    // (idle/completed/nothing-played) (re)start the surah from here.
    final ps = _player.processingState;
    if (state.currentAyah != null &&
        (ps == ProcessingState.ready || ps == ProcessingState.buffering)) {
      state = state.copyWith(continuous: true, playing: true);
      await _player.play();
    } else {
      await playSurah();
    }
  }

  Future<void> toggle() async {
    if (state.currentAyah == null) {
      await playSurah();
      return;
    }
    if (_player.playing) {
      await _player.pause();
      state = state.copyWith(playing: false);
      return;
    }
    // Resuming. If we're merely paused mid-ayah the source is still live, so
    // play() resumes from the current position. But if the ayah finished (or
    // was stopped), completion released the source and processingState is
    // idle/completed — play() would be a no-op, so (re)load the current ayah.
    final ps = _player.processingState;
    if (ps == ProcessingState.ready || ps == ProcessingState.buffering) {
      await _player.play();
      state = state.copyWith(playing: true);
    } else {
      await playAyah(state.currentAyah!, continuous: state.continuous);
    }
  }

  Future<void> next() async {
    if (!state.hasNext) return;
    await playAyah(state.currentAyah! + 1, continuous: state.continuous);
  }

  Future<void> prev() async {
    if (!state.hasPrev) return;
    await playAyah(state.currentAyah! - 1, continuous: state.continuous);
  }

  Future<void> stop() async {
    await _player.stop();
    state = state.copyWith(playing: false, continuous: false);
  }

  /// Download the loaded surah for offline use: the Arabic recitation for the
  /// current reciter AND — for any language that has one — the translation audio
  /// too, so offline playback works whether or not "read translation" is on.
  Future<void> downloadCurrentSurah() async {
    final surah = state.surah;
    final reciterId = state.reciterId;
    if (surah == null || reciterId == null || _urls.isEmpty) return;
    final lang = _ref.read(languageProvider);
    final store = _ref.read(localContentProvider);
    // Empty when the language has no translation source (e.g. Dutch).
    final trUrls = store.surahTranslationAudioUrls(lang, surah);
    // Fetch only what's missing, so the button covers "Arabic and/or
    // translation not yet downloaded" and the progress reflects real work.
    final missingAr = await _downloads.missingAyat(reciterId, surah, _urls);
    final missingTr = trUrls.isEmpty
        ? const <int, String>{}
        : await _downloads.missingAyat(_trReciterId(lang), surah, trUrls);
    final grandTotal = missingAr.length + missingTr.length;
    if (grandTotal == 0) {
      state = state.copyWith(downloaded: true);
      _ref.invalidate(downloadStatusProvider);
      return;
    }
    state = state.copyWith(
        downloading: true,
        downloadDone: 0,
        downloadTotal: grandTotal,
        downloadingTranslation: missingAr.isEmpty, // straight to translation
        clearError: true);
    try {
      if (missingAr.isNotEmpty) {
        await _downloads.downloadSurah(
          reciterId,
          surah,
          missingAr,
          onProgress: (done, _) {
            state =
                state.copyWith(downloadDone: done, downloadTotal: grandTotal);
          },
        );
      }
      if (missingTr.isNotEmpty) {
        final base = missingAr.length;
        state =
            state.copyWith(downloadingTranslation: true, downloadDone: base);
        await _downloads.downloadSurah(
          _trReciterId(lang),
          surah,
          missingTr,
          onProgress: (done, _) {
            state = state.copyWith(
                downloadDone: base + done, downloadTotal: grandTotal);
          },
        );
      }
      state = state.copyWith(downloading: false, downloaded: true);
      _ref.invalidate(downloadStatusProvider);
    } catch (e) {
      state = state.copyWith(downloading: false, error: '$e');
    }
  }

  void _onPlayerState(PlayerState s) {
    if (s.processingState == ProcessingState.completed && !_advancing) {
      _advancing = true;
      _handleCompletion().whenComplete(() => _advancing = false);
    }
  }

  Future<void> _handleCompletion() async {
    // After the Arabic recitation, optionally read the SAME ayah's translation
    // (human audio) before moving on — when "read translation" is enabled and a
    // translation source exists for the current language.
    if (_leg == _Leg.arabic && _shouldReadTranslation(state.currentAyah)) {
      await _playTranslationLeg(state.currentAyah!);
      return;
    }
    await _advanceOrStop();
  }

  /// Advance to the next ayah's Arabic (continuous mode) or stop.
  Future<void> _advanceOrStop() async {
    _leg = _Leg.arabic;
    if (state.continuous && state.hasNext) {
      await playAyah(state.currentAyah! + 1, continuous: true);
    } else {
      await _player.stop();
      state = state.copyWith(playing: false);
    }
  }

  bool _shouldReadTranslation(int? ayah) {
    if (ayah == null || !_ref.read(playTranslationProvider)) return false;
    final lang = _ref.read(languageProvider);
    return _ref.read(localContentProvider).hasTranslationAudio(lang);
  }

  /// Play the current ayah's translation recitation — local file if downloaded,
  /// else streamed. On any failure, don't stall the surah — advance instead.
  Future<void> _playTranslationLeg(int ayah) async {
    final surah = state.surah;
    final lang = _ref.read(languageProvider);
    Uri? uri;
    if (surah != null) {
      final local = await _downloads.localPath(_trReciterId(lang), surah, ayah);
      if (local != null) {
        uri = Uri.file(local);
      } else {
        final url =
            _ref.read(localContentProvider).translationAudioUrl(lang, surah, ayah);
        if (url != null) uri = Uri.parse(url);
      }
    }
    if (uri == null) {
      await _advanceOrStop();
      return;
    }
    _leg = _Leg.translation;
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _player.setAudioSource(AudioSource.uri(uri));
      state = state.copyWith(loading: false, playing: true);
      await _player.play();
    } catch (_) {
      await _advanceOrStop();
    }
  }

  // ---- translation offline helpers ----

  /// Synthetic "reciter id" the download store uses to keep a language's
  /// translation audio separate from the Arabic reciters on disk.
  String _trReciterId(String lang) => translationDownloadOwner(lang);

  /// A surah counts as fully "downloaded" when its Arabic is present — and, for
  /// languages that have a translation source, the translation audio too (the
  /// Download button always fetches both, independent of the read-translation
  /// toggle).
  Future<bool> _computeDownloaded(
      int surah, String reciterId, int ayahCount) async {
    final arabic =
        await _downloads.isSurahDownloaded(reciterId, surah, ayahCount);
    final lang = _ref.read(languageProvider);
    if (!arabic ||
        !_ref.read(localContentProvider).hasTranslationAudio(lang)) {
      return arabic;
    }
    return _downloads.isSurahDownloaded(_trReciterId(lang), surah, ayahCount);
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}

final audioControllerProvider =
    StateNotifierProvider<AudioController, AudioState>((ref) {
  return AudioController(ref);
});
