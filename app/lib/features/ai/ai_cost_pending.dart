import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_usage.dart';

/// Costs metered BEFORE the answer they belong to exists: the speech-to-text
/// and transcript-refine calls in the input bar, and the home command-router
/// call. They are held here until the answer turn drains them, so each
/// response's total covers everything spent producing it — not just the chat
/// calls made inside the Ask sheet.
class PendingAiCost {
  const PendingAiCost(this.chat, this.extra);
  final List<AiCallUsage> chat; // token-priced chat calls (router, refine)
  final List<AiExtraCost> extra; // flat-cost calls (Whisper STT)
  bool get isEmpty => chat.isEmpty && extra.isEmpty;
}

class PendingAiCostNotifier extends StateNotifier<PendingAiCost> {
  PendingAiCostNotifier() : super(const PendingAiCost([], []));

  void addChat(List<AiCallUsage> calls) {
    if (calls.isEmpty) return;
    state = PendingAiCost([...state.chat, ...calls], state.extra);
  }

  void addExtra(AiExtraCost cost) {
    if (cost.costUsd <= 0) return;
    state = PendingAiCost(state.chat, [...state.extra, cost]);
  }

  /// Take everything accumulated so far and reset — called by the answer turn
  /// that these costs produced, which folds them into its own total.
  PendingAiCost drain() {
    final out = state;
    state = const PendingAiCost([], []);
    return out;
  }

  /// Discard accumulated costs that won't produce a displayed answer (e.g. the
  /// router resolved the input to a navigation / recite command).
  void clear() => state = const PendingAiCost([], []);
}

final pendingAiCostProvider =
    StateNotifierProvider<PendingAiCostNotifier, PendingAiCost>(
        (ref) => PendingAiCostNotifier());
