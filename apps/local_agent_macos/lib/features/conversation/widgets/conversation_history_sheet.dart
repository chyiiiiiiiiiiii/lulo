import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../conversation_storage_service.dart';
import 'conversation_content_column.dart';

/// Every stored conversation, shown over the current one.
///
/// Each row opens its conversation; forgetting one is a press away on the
/// row itself, and a new conversation starts from here rather than from a
/// mode the composer would have to be in.
final class ConversationHistorySheet extends StatelessWidget {
  /// Creates the conversation list surface.
  const ConversationHistorySheet({
    required this.conversations,
    required this.onOpen,
    required this.onNew,
    required this.onDelete,
    required this.onClose,
    super.key,
  });

  /// The stored conversations, most recently spoken-in first.
  final List<ConversationSummary> conversations;

  /// Called with the conversation the user chose to return to.
  final ValueChanged<ConversationId> onOpen;

  /// Called when the user starts a new conversation.
  final VoidCallback onNew;

  /// Called with the conversation the user chose to forget.
  final ValueChanged<ConversationId> onDelete;

  /// Called when the user is finished looking.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      key: const Key('conversation-history-sheet'),
      color: colors.surface,
      // Esc is how a Mac user backs out of anything transient — the same
      // rule the settings follow. Autofocus so the key lands here while the
      // sheet is what they are looking at.
      child: Focus(
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            onClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                // The conversation's own grid: the window buttons live on the
                // line above, so the title has nothing to clear.
                padding: const EdgeInsets.fromLTRB(
                  conversationContentMargin,
                  28,
                  16,
                  8,
                ),
                child: Row(
                  children: <Widget>[
                    Text(
                      'Conversations',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      key: const Key('conversation-new-button'),
                      tooltip: 'New conversation',
                      icon: const Icon(Icons.add_rounded),
                      onPressed: onNew,
                    ),
                    IconButton(
                      key: const Key('conversation-history-close-button'),
                      tooltip: 'Close the conversation list',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ConversationContentColumn(
                  child: conversations.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(
                            conversationContentMargin,
                          ),
                          child: Text(
                            'Nothing yet',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: conversationContentMargin,
                          ),
                          itemCount: conversations.length,
                          itemBuilder: (BuildContext context, int index) {
                            final ConversationSummary conversation =
                                conversations[index];
                            return ListTile(
                              key: Key(
                                'conversation-row-${conversation.id.value}',
                              ),
                              title: Text(
                                conversation.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => onOpen(conversation.id),
                              trailing: IconButton(
                                key: Key(
                                  'conversation-delete-'
                                  '${conversation.id.value}',
                                ),
                                tooltip: 'Forget this conversation',
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () => onDelete(conversation.id),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
