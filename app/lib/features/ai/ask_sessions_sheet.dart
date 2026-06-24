import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ask_session.dart';
import 'ask_sessions_controller.dart';

/// Lists the user's saved "Ask the Quran" conversations and lets them start a
/// new one or continue a previous one. Pops with the chosen [AskSession]; the
/// caller then opens the conversation sheet.
class AskSessionsSheet extends ConsumerWidget {
  const AskSessionsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sessions = ref.watch(askSessionsProvider);
    final controller = ref.read(askSessionsProvider.notifier);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Ask the Quran',
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(controller.newSession()),
              icon: const Icon(Icons.add),
              label: const Text('New conversation'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
          if (sessions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('Recent conversations',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ),
          Expanded(
            child: sessions.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        'No conversations yet.\nStart one to ask about any topic in the Quran.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: sessions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (_, i) {
                      final s = sessions[i];
                      return Dismissible(
                        key: ValueKey(s.id),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => controller.deleteSession(s.id),
                        background: Container(
                          alignment: AlignmentDirectional.centerEnd,
                          padding: const EdgeInsets.only(right: 24),
                          color: cs.errorContainer,
                          child: Icon(Icons.delete_outline,
                              color: cs.onErrorContainer),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: cs.primary.withValues(alpha: 0.15),
                            child: Text('${s.turns.length}',
                                style: TextStyle(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w700)),
                          ),
                          title: Text(s.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Row(
                            children: [
                              if (s.scopeLabel.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: cs.secondaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(s.scopeLabel,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                          color: cs.onSecondaryContainer)),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  '${s.turns.length}/${AskSession.maxQuestions} questions · ${_ago(s.updatedAt)}',
                                  style: theme.textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).pop(s),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static String _ago(int epochMs) {
    final d = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(epochMs));
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${(d.inDays / 7).floor()}w ago';
  }
}
