import 'package:flutter/material.dart';

import 'ai_usage.dart';

/// Compact per-model token usage + total USD cost for one AI response, including
/// the non-token costs (speech-to-text, read-aloud TTS) that the response
/// incurred. Shown under each answer and persisted with the turn, so reopening a
/// past conversation shows the same totals.
class UsageFooter extends StatelessWidget {
  const UsageFooter({super.key, required this.usage, this.extraCosts = const []});
  final List<AiCallUsage> usage;
  final List<AiExtraCost> extraCosts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final models = aggregateUsage(usage);
    final total = totalUsageCost(usage) + extraCostsTotal(extraCosts);
    // Sum the non-token costs by kind for a single line each.
    var stt = 0.0, tts = 0.0;
    var sttEst = false, ttsEst = false;
    for (final c in extraCosts) {
      if (c.kind == 'stt') {
        stt += c.costUsd;
        sttEst = sttEst || c.estimated;
      } else if (c.kind == 'tts') {
        tts += c.costUsd;
        ttsEst = ttsEst || c.estimated;
      }
    }
    final small =
        theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant);
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_outlined, size: 15, color: cs.primary),
              const SizedBox(width: 6),
              Text('Tokens & cost',
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.primary, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(formatCost(total),
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.primary, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          for (final m in models)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${m.model} · ${formatTokens(m.inputTokens)} in'
                      '${m.cachedTokens > 0 ? ' (${formatTokens(m.cachedTokens)} cached)' : ''}'
                      ' · ${formatTokens(m.outputTokens)} out',
                      style: small,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(formatCost(m.costUsd), style: small),
                ],
              ),
            ),
          if (stt > 0)
            _extraRow('Speech-to-text${sttEst ? ' (est.)' : ''}', stt, small),
          if (tts > 0)
            _extraRow('Read aloud (TTS)${ttsEst ? ' (est.)' : ''}', tts, small),
        ],
      ),
    );
  }

  Widget _extraRow(String label, double usd, TextStyle? small) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Expanded(child: Text(label, style: small)),
            const SizedBox(width: 8),
            Text(formatCost(usd), style: small),
          ],
        ),
      );
}
