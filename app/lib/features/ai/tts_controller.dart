import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../settings/ai_settings_controller.dart';

/// A stable id for a piece of text to read — used so each answer part's player
/// can tell whether IT is the one currently loaded in the shared TTS player.
String ttsIdFor(String text) => 'p${text.hashCode}';

/// What the read-aloud (TTS) player is doing. One shared player serves every
/// part; [currentId] says which part is loaded.
class TtsState {
  final String? currentId; // the part loaded in the player
  final String? loadingId; // a part currently being synthesized
  final bool playing;
  final Duration position;
  final Duration duration;
  final double volume; // 0..1
  final String? error;

  const TtsState({
    this.currentId,
    this.loadingId,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.error,
  });

  bool get active => currentId != null || loadingId != null;

  TtsState copyWith({
    String? currentId,
    String? loadingId,
    bool? playing,
    Duration? position,
    Duration? duration,
    double? volume,
    String? error,
    bool clearCurrent = false,
    bool clearLoading = false,
    bool clearError = true,
  }) {
    return TtsState(
      currentId: clearCurrent ? null : (currentId ?? this.currentId),
      loadingId: clearLoading ? null : (loadingId ?? this.loadingId),
      playing: playing ?? this.playing,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      error: clearError ? error : (error ?? this.error),
    );
  }
}

class _Clip {
  _Clip(this.id, this.text, this.voice, this.speed);
  final String id;
  final String text;
  final String voice;
  final double speed;
  Future<List<int>>? bytes; // synthesis is started EAGERLY on creation
}

/// Reads AI answers aloud via OpenAI TTS on one shared player (separate from
/// Quran recitation). Each part is addressed by a stable [ttsIdFor] id so the UI
/// can render per-part controls (play/pause, seek, volume).
///
/// Two-part answers stream: [play] the first part, then [enqueue] the second —
/// the second's MP3 is synthesized in the BACKGROUND while the first plays, so
/// it starts the instant the first ends.
class TtsController extends StateNotifier<TtsState> {
  TtsController(this._ref) : super(const TtsState()) {
    _player = AudioPlayer();
    _posSub = _player.positionStream.listen(
        (p) => state = state.copyWith(position: p));
    _durSub = _player.durationStream
        .listen((d) => state = state.copyWith(duration: d ?? Duration.zero));
    _stateSub = _player.playerStateStream
        .listen((s) => state = state.copyWith(playing: s.playing));
  }

  final Ref _ref;
  late final AudioPlayer _player;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  final List<_Clip> _queue = [];
  bool _working = false;
  int _gen = 0; // bumped by play/stop to abort the current chain
  int _fileSeq = 0;

  _Clip _make(String id, String text, String? voice, double? speed) {
    final c = _Clip(
      id,
      text.trim(),
      voice ?? _ref.read(ttsVoiceProvider),
      speed ?? _ref.read(ttsSpeedProvider),
    );
    c.bytes = _synth(c); // start synthesizing immediately (background)
    return c;
  }

  Future<List<int>> _synth(_Clip c) => _ref
      .read(openAiClientProvider)
      .synthesizeSpeech(voice: c.voice, text: c.text, speed: c.speed);

  /// Play [text] now (as part [id]), replacing anything queued/playing.
  Future<void> play(String id, String text,
      {String? voice, double? speed}) async {
    if (text.trim().isEmpty) return;
    _gen++;
    _queue
      ..clear()
      ..add(_make(id, text, voice, speed));
    await _player.stop();
    unawaited(_drain(_gen));
  }

  /// Queue [text] (as part [id]) to play after the current part — its audio is
  /// synthesized in the background right away so there's no gap.
  Future<void> enqueue(String id, String text,
      {String? voice, double? speed}) async {
    if (text.trim().isEmpty) return;
    _queue.add(_make(id, text, voice, speed));
    unawaited(_drain(_gen));
  }

  Future<void> _drain(int gen) async {
    if (_working) return;
    _working = true;
    try {
      while (_queue.isNotEmpty && gen == _gen) {
        final clip = _queue.removeAt(0);
        state = state.copyWith(currentId: clip.id, loadingId: clip.id);
        List<int> bytes;
        try {
          bytes = await (clip.bytes ??= _synth(clip));
        } catch (e) {
          if (gen == _gen) {
            state = state.copyWith(error: '$e', clearLoading: true);
          }
          continue;
        }
        if (gen != _gen) break;
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/tts_${++_fileSeq}.mp3');
        await file.writeAsBytes(bytes, flush: true);
        if (gen != _gen) break;
        await _player.setVolume(state.volume);
        await _player.setFilePath(file.path);
        state = state.copyWith(currentId: clip.id, playing: true, clearLoading: true);
        _player.play();
        await _awaitEnd(gen); // returns at end-of-clip or when aborted/replaced
      }
    } finally {
      _working = false;
      if (gen == _gen && _queue.isEmpty) {
        state = state.copyWith(playing: false, clearLoading: true);
      }
    }
  }

  /// Wait until the current clip reaches its end. A pause does NOT advance (the
  /// stream stays `ready`); a stop/replace bumps [_gen] so we bail.
  Future<void> _awaitEnd(int gen) async {
    await for (final s in _player.processingStateStream) {
      if (gen != _gen) return;
      if (s == ProcessingState.completed) return;
    }
  }

  void toggle() {
    if (state.currentId == null) return;
    _player.playing ? _player.pause() : _player.play();
  }

  void seekTo(Duration p) => _player.seek(_clampPos(p));

  void seekBy(int seconds) =>
      _player.seek(_clampPos(state.position + Duration(seconds: seconds)));

  Duration _clampPos(Duration p) {
    if (p < Duration.zero) return Duration.zero;
    if (state.duration > Duration.zero && p > state.duration) {
      return state.duration;
    }
    return p;
  }

  Future<void> setVolume(double v) async {
    final vol = v.clamp(0.0, 1.0);
    await _player.setVolume(vol);
    state = state.copyWith(volume: vol);
  }

  Future<void> stop() async {
    _gen++;
    _queue.clear();
    await _player.stop();
    state = TtsState(volume: state.volume);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}

final ttsControllerProvider =
    StateNotifierProvider<TtsController, TtsState>((ref) => TtsController(ref));

/// Strip Markdown so the narrator reads clean prose (no `*`, `#`, `` ` ``, links).
String plainForSpeech(String md) {
  var s = md;
  s = s.replaceAll(RegExp(r'```[\s\S]*?```'), ' '); // code/verse fences
  s = s.replaceAll(RegExp(r'`([^`]*)`'), r'$1'); // inline code
  s = s.replaceAll(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), r'$1'); // links/images
  s = s.replaceAll(RegExp(r'[*_#>~|]'), ''); // emphasis / headings / rules
  s = s.replaceAll(RegExp(r'\n{2,}'), '. '); // paragraph breaks → pause
  s = s.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  return s.trim();
}
