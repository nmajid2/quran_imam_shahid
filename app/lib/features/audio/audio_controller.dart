import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/providers.dart';
import '../../data/models/reciter.dart';
import 'download_manager.dart';

final downloadManagerProvider =
    Provider<DownloadManager>((ref) => DownloadManager());

/// Reciter catalog from the gateway (default + list).
final recitersProvider = FutureProvider<ReciterCatalog>((ref) {
  return ref.watch(apiClientProvider).listReciters();
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
      _urls = await _ref.read(apiClientProvider).surahAudioUrls(reciterId, surah);
      final downloaded =
          await _downloads.isSurahDownloaded(reciterId, surah, ayahCount);
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

  /// Download the loaded surah's audio for the current reciter.
  Future<void> downloadCurrentSurah() async {
    final surah = state.surah;
    final reciterId = state.reciterId;
    if (surah == null || reciterId == null || _urls.isEmpty) return;
    state = state.copyWith(
        downloading: true, downloadDone: 0, downloadTotal: _urls.length, clearError: true);
    try {
      await _downloads.downloadSurah(
        reciterId,
        surah,
        _urls,
        onProgress: (done, total) {
          state = state.copyWith(downloadDone: done, downloadTotal: total);
        },
      );
      state = state.copyWith(downloading: false, downloaded: true);
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
    if (state.continuous && state.hasNext) {
      await playAyah(state.currentAyah! + 1, continuous: true);
    } else {
      await _player.stop();
      state = state.copyWith(playing: false);
    }
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
