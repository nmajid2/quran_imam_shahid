// Token usage + USD pricing for the OpenAI models the app uses, so each AI
// answer can show how many tokens each model spent and what it cost.

/// Per-1M-token prices (USD) for a chat model.
class AiPricing {
  const AiPricing(this.input, this.cachedInput, this.output);
  final double input; // uncached prompt tokens
  final double cachedInput; // cached prompt tokens
  final double output; // completion tokens

  /// Prices per 1,000,000 tokens. Keep in sync with the OpenAI pricing page.
  static const Map<String, AiPricing> table = {
    'gpt-4o-mini': AiPricing(0.15, 0.075, 0.60),
    'gpt-4o': AiPricing(2.50, 1.25, 10.00),
    'gpt-5-mini': AiPricing(0.25, 0.025, 2.00),
    'gpt-5.4-mini': AiPricing(0.75, 0.075, 4.50),
    'gpt-5.1': AiPricing(1.25, 0.125, 10.00),
  };

  static AiPricing? forModel(String model) => table[model];
}

/// One model call's token usage.
class AiCallUsage {
  const AiCallUsage({
    required this.model,
    required this.inputTokens,
    this.cachedTokens = 0,
    required this.outputTokens,
  });

  final String model;
  final int inputTokens; // prompt tokens (includes any cached)
  final int cachedTokens; // the cached subset of inputTokens
  final int outputTokens; // completion tokens

  /// Cost of this call in USD (0 if the model isn't in the pricing table).
  double get costUsd {
    final p = AiPricing.forModel(model);
    if (p == null) return 0;
    final uncached = (inputTokens - cachedTokens).clamp(0, inputTokens);
    return (uncached * p.input +
            cachedTokens * p.cachedInput +
            outputTokens * p.output) /
        1000000.0;
  }

  Map<String, dynamic> toJson() => {
        'model': model,
        'in': inputTokens,
        'cached': cachedTokens,
        'out': outputTokens,
      };

  factory AiCallUsage.fromJson(Map<String, dynamic> j) => AiCallUsage(
        model: (j['model'] ?? '') as String,
        inputTokens: (j['in'] as num?)?.toInt() ?? 0,
        cachedTokens: (j['cached'] as num?)?.toInt() ?? 0,
        outputTokens: (j['out'] as num?)?.toInt() ?? 0,
      );
}

/// Aggregated usage for one model across a question's calls.
class ModelUsage {
  ModelUsage(this.model);
  final String model;
  int inputTokens = 0;
  int cachedTokens = 0;
  int outputTokens = 0;

  double get costUsd => AiCallUsage(
        model: model,
        inputTokens: inputTokens,
        cachedTokens: cachedTokens,
        outputTokens: outputTokens,
      ).costUsd;
}

/// Group [calls] by model (summing tokens), most-expensive first.
List<ModelUsage> aggregateUsage(List<AiCallUsage> calls) {
  final map = <String, ModelUsage>{};
  for (final c in calls) {
    final m = map.putIfAbsent(c.model, () => ModelUsage(c.model));
    m.inputTokens += c.inputTokens;
    m.cachedTokens += c.cachedTokens;
    m.outputTokens += c.outputTokens;
  }
  final list = map.values.toList()
    ..sort((a, b) => b.costUsd.compareTo(a.costUsd));
  return list;
}

double totalUsageCost(List<AiCallUsage> calls) =>
    calls.fold(0.0, (s, c) => s + c.costUsd);

// ---- Speech-to-text (Whisper) ----
//
// whisper-1 is billed by audio length at $0.006 / minute and returns NO token
// counts, so we derive the cost from the recording's duration.
const double kWhisperPerMinute = 0.006;

/// Cost (USD) of transcribing [audio] of the given length with whisper-1.
double estimateSttCost(Duration audio) => audio.inMilliseconds <= 0
    ? 0
    : audio.inMilliseconds / 60000.0 * kWhisperPerMinute;

// ---- Non-token costs attached to a response ----

/// A metered AI cost that is NOT token-priced chat usage: speech-to-text
/// (Whisper, per-minute) or text-to-speech (estimated). Carries a ready USD
/// cost so it can sit alongside [AiCallUsage] in a response's total. [kind] is
/// `'stt'` or `'tts'`; [estimated] is true for endpoints with no exact billing.
class AiExtraCost {
  const AiExtraCost({
    required this.kind,
    required this.costUsd,
    this.estimated = false,
  });

  final String kind; // 'stt' | 'tts'
  final double costUsd;
  final bool estimated;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'usd': costUsd,
        if (estimated) 'est': true,
      };

  factory AiExtraCost.fromJson(Map<String, dynamic> j) => AiExtraCost(
        kind: (j['kind'] ?? '') as String,
        costUsd: (j['usd'] as num?)?.toDouble() ?? 0,
        estimated: j['est'] == true,
      );
}

double extraCostsTotal(List<AiExtraCost> costs) =>
    costs.fold(0.0, (s, c) => s + c.costUsd);

// ---- Text-to-speech (estimated) ----
//
// gpt-4o-mini-tts is billed per token: $0.60 / 1M text-input tokens and
// $12.00 / 1M audio-output tokens. The speech endpoint returns NO token counts,
// so we estimate: input tokens from the text, and audio-output tokens from the
// real playback duration (~1,250 audio tokens/min, i.e. OpenAI's ~$0.015/min;
// matches the documented ~6 audio tokens per text token). Falls back to the 6×
// ratio before the audio's duration is known.
const double kTtsTextInputPer1M = 0.60;
const double kTtsAudioOutputPer1M = 12.00;
const double kTtsAudioTokensPerMinute = 1250.0;
const int kTtsAudioTokensPerTextToken = 6;

/// Rough token count for [text] (no tokenizer on-device): Latin ≈ 4 chars/token,
/// other scripts (Persian/Arabic) ≈ 2 chars/token. Good enough for the small
/// text-input term; the dominant audio term uses duration.
int estimateTextTokens(String text) {
  var ascii = 0, other = 0;
  for (final r in text.runes) {
    if (r <= 0x7F) {
      ascii++;
    } else {
      other++;
    }
  }
  final t = (ascii / 4 + other / 2).ceil();
  return t < 1 ? 1 : t;
}

class TtsCostEstimate {
  const TtsCostEstimate(this.inputTokens, this.audioTokens, this.costUsd,
      {this.fromDuration = false});
  final int inputTokens;
  final int audioTokens;
  final double costUsd;
  final bool fromDuration; // true once based on real audio length
}

/// Estimate the cost of reading [text] aloud. When [audioDuration] is known
/// (after the clip loads), the audio-token term uses it; otherwise the 6× ratio.
TtsCostEstimate estimateTtsCost(String text, {Duration? audioDuration}) {
  final inTok = estimateTextTokens(text);
  final int audioTok;
  final bool fromDur;
  if (audioDuration != null && audioDuration > Duration.zero) {
    audioTok =
        (audioDuration.inMilliseconds / 60000.0 * kTtsAudioTokensPerMinute)
            .round();
    fromDur = true;
  } else {
    audioTok = inTok * kTtsAudioTokensPerTextToken;
    fromDur = false;
  }
  final cost =
      (inTok * kTtsTextInputPer1M + audioTok * kTtsAudioOutputPer1M) / 1000000.0;
  return TtsCostEstimate(inTok, audioTok, cost, fromDuration: fromDur);
}

/// "$0.0123" with enough precision for fractions of a cent.
String formatCost(double usd) {
  if (usd <= 0) return r'$0';
  if (usd < 0.01) return '\$${usd.toStringAsFixed(4)}';
  return '\$${usd.toStringAsFixed(3)}';
}

/// "1,234" with thousands separators.
String formatTokens(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
