import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../settings/ai_settings_controller.dart';
import 'ai_cost_pending.dart';
import 'ai_usage.dart';

enum _Mic { idle, recording, transcribing }

enum _Step { transcribing, refining }

/// The AI question input: a text field + send button, plus a mic that records
/// the user's voice, transcribes it (OpenAI Whisper, in [lang]), drops the
/// transcript into the box and auto-submits — so the spoken question runs exactly
/// like a typed one (and the transcript stays visible as the asked question).
///
/// Listening shows a live waveform + pulsing mic; transcribing shows a shimmer.
class AiInputBar extends ConsumerStatefulWidget {
  const AiInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hint,
    required this.isRtl,
    required this.lang,
    required this.onSubmit,
    this.onChanged,
    this.sheetStyle = true,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String hint;
  final bool isRtl;
  final String lang;

  /// Submit the current text. [fromVoice] is true when the submission came from
  /// the mic (transcribed speech) — the caller uses it to read the answer aloud.
  final void Function({bool fromVoice}) onSubmit;

  /// Live text changes (e.g. the home box filters the surah list as you type).
  final ValueChanged<String>? onChanged;

  /// `true` = bottom-sheet footer styling (top border, keyboard inset). `false` =
  /// embedded styling for the home page (rounded, no border/inset).
  final bool sheetStyle;

  @override
  ConsumerState<AiInputBar> createState() => _AiInputBarState();
}

class _AiInputBarState extends ConsumerState<AiInputBar>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  late final AnimationController _anim;
  _Mic _mic = _Mic.idle;
  _Step _step = _Step.transcribing;
  String? _path;
  DateTime? _recordStart; // to derive the Whisper (per-minute) cost

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
  }

  @override
  void dispose() {
    _anim.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    switch (_mic) {
      case _Mic.idle:
        await _start();
      case _Mic.recording:
        await _stop();
      case _Mic.transcribing:
        break; // busy
    }
  }

  Future<void> _start() async {
    if (!widget.enabled) return;
    try {
      if (!await _recorder.hasPermission()) {
        _toast('Microphone permission is needed for voice questions.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/q_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path);
      if (!mounted) return;
      widget.focusNode.unfocus();
      setState(() {
        _path = path;
        _recordStart = DateTime.now();
        _mic = _Mic.recording;
      });
      _anim.repeat();
    } catch (e) {
      _toast('Could not start recording: $e');
      _reset();
    }
  }

  Future<void> _stop() async {
    // Keep the controller animating so the busy shimmer moves.
    setState(() {
      _mic = _Mic.transcribing;
      _step = _Step.transcribing;
    });
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = _path;
    }
    // Recording length drives the Whisper (per-minute) cost.
    final recordedFor =
        _recordStart == null ? Duration.zero : DateTime.now().difference(_recordStart!);
    if (path == null) {
      _reset();
      return;
    }
    try {
      final client = ref.read(openAiClientProvider);
      final model = ref.read(refineModelProvider);
      final pending = ref.read(pendingAiCostProvider.notifier);
      final raw = await client.transcribe(filePath: path, lang: widget.lang);
      if (!mounted) return;
      if (raw.isEmpty) {
        _toast("Didn't catch that — try again.");
        _reset();
        return;
      }
      // Meter the speech-to-text (charged whatever the result); held in the
      // pending bucket until the answer turn folds it into that response's total.
      pending.addExtra(AiExtraCost(
          kind: 'stt', costUsd: estimateSttCost(recordedFor), estimated: true));
      // Context-aware cleanup so misheard words/names are fixed before the user
      // sees and the AI answers (falls back to the raw transcript on failure).
      setState(() => _step = _Step.refining);
      final refineUsage = <AiCallUsage>[];
      final text = await client.refineTranscript(
          model: model, lang: widget.lang, text: raw, usage: refineUsage);
      pending.addChat(refineUsage);
      if (!mounted) return;
      widget.controller.text = text;
      _reset();
      // Auto-send; corrected transcript shows as the question. fromVoice lets the
      // sheet read the answer back aloud.
      widget.onSubmit(fromVoice: true);
    } catch (e) {
      if (mounted) _toast('Transcription failed: $e');
      _reset();
    } finally {
      _deleteTemp(path);
    }
  }

  void _reset() {
    _anim.stop();
    _anim.value = 0;
    if (mounted) setState(() => _mic = _Mic.idle);
  }

  void _deleteTemp(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom > 0
        ? media.viewInsets.bottom
        : media.viewPadding.bottom;
    final recording = _mic == _Mic.recording;
    final transcribing = _mic == _Mic.transcribing;

    return Container(
      padding: widget.sheetStyle
          ? EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomInset)
          : EdgeInsets.zero,
      decoration: widget.sheetStyle
          ? BoxDecoration(
              color: cs.surface,
              border: Border(
                top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _MicButton(
            anim: _anim,
            recording: recording,
            transcribing: transcribing,
            enabled: widget.enabled || recording,
            onTap: _toggle,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: recording
                  ? _Listening(
                      key: const ValueKey('rec'),
                      anim: _anim,
                      label: _listeningLabel)
                  : transcribing
                      ? _Transcribing(
                          key: const ValueKey('tr'),
                          anim: _anim,
                          label: _step == _Step.refining
                              ? _refiningLabel
                              : _transcribingLabel)
                      : TextField(
                          key: const ValueKey('field'),
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          enabled: widget.enabled,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.search,
                          textDirection: widget.isRtl
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          onChanged: widget.onChanged,
                          onSubmitted: (_) => widget.onSubmit(),
                          decoration: InputDecoration(
                            hintText: widget.hint,
                            filled: true,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed:
                (widget.enabled && !recording && !transcribing) ? widget.onSubmit : null,
            icon: const Icon(Icons.send_rounded),
            tooltip: 'Ask',
          ),
        ],
      ),
    );
  }

  String get _listeningLabel => switch (widget.lang) {
        'fa' => 'در حال شنیدن… برای پایان، ضربه بزنید',
        'nl' => 'Aan het luisteren… tik om te stoppen',
        _ => 'Listening… tap the mic to stop',
      };

  String get _transcribingLabel => switch (widget.lang) {
        'fa' => 'در حال تبدیل گفتار به متن…',
        'nl' => 'Spraak omzetten naar tekst…',
        _ => 'Transcribing…',
      };

  String get _refiningLabel => switch (widget.lang) {
        'fa' => 'در حال اصلاح متن…',
        'nl' => 'Tekst verfijnen…',
        _ => 'Polishing the text…',
      };
}

/// Circular mic / stop button with an animated pulse-ring halo while recording.
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.anim,
    required this.recording,
    required this.transcribing,
    required this.enabled,
    required this.onTap,
  });
  final AnimationController anim;
  final bool recording;
  final bool transcribing;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const size = 46.0;
    final base = recording ? cs.error : cs.primary;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (recording)
            AnimatedBuilder(
              animation: anim,
              builder: (_, __) => CustomPaint(
                size: const Size(size, size),
                painter: _PulsePainter(anim.value, base),
              ),
            ),
          Material(
            color: enabled
                ? base.withValues(alpha: recording ? 0.95 : 0.14)
                : cs.surfaceContainerHighest,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled && !transcribing ? onTap : null,
              child: SizedBox(
                width: size,
                height: size,
                child: transcribing
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Icon(
                        recording ? Icons.stop_rounded : Icons.mic_rounded,
                        color: recording ? cs.onError : base,
                        size: 24,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Concentric expanding rings that fade as they grow — the "listening" halo.
class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rMin = size.width * 0.32;
    final rMax = size.width * 0.62;
    for (var i = 0; i < 2; i++) {
      final p = (t + i * 0.5) % 1.0;
      final radius = rMin + (rMax - rMin) * p;
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: (1 - p) * 0.35);
      canvas.drawCircle(c, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t || old.color != color;
}

/// A live equalizer waveform + label, shown while recording.
class _Listening extends StatelessWidget {
  const _Listening({super.key, required this.anim, required this.label});
  final AnimationController anim;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: anim,
            builder: (_, __) => CustomPaint(
              size: const Size(56, 22),
              painter: _WavePainter(anim.value, cs.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 7;
    final gap = size.width / (bars * 2 - 1);
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = gap;
    for (var i = 0; i < bars; i++) {
      final phase = t * 2 * math.pi + i * 0.9;
      final amp = (0.35 + 0.65 * (0.5 + 0.5 * math.sin(phase)));
      final h = size.height * amp;
      final x = gap / 2 + i * gap * 2;
      final y0 = (size.height - h) / 2;
      canvas.drawLine(Offset(x, y0), Offset(x, y0 + h), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.t != t || old.color != color;
}

/// A shimmering label shown while the audio is being transcribed.
class _Transcribing extends StatelessWidget {
  const _Transcribing({super.key, required this.anim, required this.label});
  final AnimationController anim;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 46,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
      ),
      child: AnimatedBuilder(
        animation: anim,
        builder: (context, _) {
          final t = anim.isAnimating ? anim.value : 0.0;
          return ShaderMask(
            shaderCallback: (rect) {
              final dx = (t * 2 - 0.5) * rect.width;
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  cs.onSurfaceVariant.withValues(alpha: 0.45),
                  cs.primary,
                  cs.onSurfaceVariant.withValues(alpha: 0.45),
                ],
                stops: [
                  (dx / rect.width - 0.15).clamp(0.0, 1.0),
                  (dx / rect.width).clamp(0.0, 1.0),
                  (dx / rect.width + 0.15).clamp(0.0, 1.0),
                ],
              ).createShader(rect);
            },
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          );
        },
      ),
    );
  }
}
