import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../agent_profile/agent_profile_store.dart';
import 'presence_notice.dart';

/// What glancing at a lit orb shows: the thing Lulo noticed, and the ways out.
///
/// For a memory write, that is the sentence that was kept, who decided —
/// the same provenance line the settings sheet renders — and the forget
/// button, so the one-tap answer to "I did not want that kept" is right
/// where the fact is first seen rather than three sheets away.
final class NoticeGlanceCard extends StatelessWidget {
  /// Creates the card for [notice].
  const NoticeGlanceCard({
    required this.notice,
    required this.profile,
    required this.onDismiss,
    super.key,
  });

  /// The notice the user opened.
  final PresenceNotice notice;

  /// Where the kept memory lives, for the forget button to act on.
  final AgentProfileStore profile;

  /// Called when the card has said its piece, whichever way it ends.
  final VoidCallback onDismiss;

  void _forget() {
    // Against the profile as it is now, not as it was when the notice lit:
    // the same staleness rule every write in this app follows.
    final AgentProfile current = profile.current;
    unawaited(
      profile.save(
        current.copyWith(
          memories: <AgentMemory>[
            for (final AgentMemory memory in current.memories)
              if (memory.content != notice.summary) memory,
          ],
        ),
      ),
    );
    onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations words = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              key: const Key('notice-glance-card'),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      words.profileMemoryByAgent,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(notice.summary, style: theme.textTheme.bodyMedium),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        TextButton(
                          key: const Key('notice-forget'),
                          onPressed: _forget,
                          child: Text(words.profileForget),
                        ),
                        TextButton(
                          key: const Key('notice-dismiss'),
                          onPressed: onDismiss,
                          child: Text(words.noticeDismiss),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
