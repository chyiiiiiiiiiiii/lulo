import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../conversation_storage_service.dart';
import 'conversation_content_column.dart';

/// Every stored conversation, shown over the current one.
///
/// Each row opens its conversation; forgetting one is a press away on the
/// row itself, and a new conversation starts from here rather than from a
/// mode the composer would have to be in.
///
/// Everything past opening and forgetting is optional, and absent rather than
/// dead where there is nothing behind it: the deterministic preview and the
/// widget tests have no store to search, rename or pin in.
final class ConversationHistorySheet extends StatefulWidget {
  /// Creates the conversation list surface.
  const ConversationHistorySheet({
    required this.conversations,
    required this.onOpen,
    required this.onNew,
    required this.onDelete,
    required this.onClose,
    this.onExport,
    this.onSearch,
    this.onRename,
    this.onPin,
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

  /// Called with the conversation the user chose to save out, or null where
  /// there is nowhere to save it to.
  final ValueChanged<ConversationId>? onExport;

  /// Called as the user types, or null where there is nothing to search.
  final ValueChanged<String>? onSearch;

  /// Called with a conversation's new name, or null where nothing can be
  /// renamed.
  final void Function(ConversationId conversationId, String title)? onRename;

  /// Called when a conversation is kept at the top or let go, or null where
  /// nothing can be pinned.
  final void Function(ConversationId conversationId, {required bool pinned})?
  onPin;

  @override
  State<ConversationHistorySheet> createState() =>
      _ConversationHistorySheetState();
}

final class _ConversationHistorySheetState
    extends State<ConversationHistorySheet> {
  final TextEditingController _search = TextEditingController();

  /// Waits for the typing to stop before asking the store.
  ///
  /// The search is a substring scan of every turn plus a title lookup per
  /// conversation, and firing it on every keystroke asks that question five
  /// times to answer it once.
  Timer? _searchDebounce;

  /// How long the typing has to stop for.
  static const Duration _searchQuiet = Duration(milliseconds: 180);

  /// The conversation being renamed, and the name so far.
  ConversationId? _renaming;
  TextEditingController? _newName;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _newName?.dispose();
    super.dispose();
  }

  void _beginRename(ConversationSummary conversation) {
    setState(() {
      _renaming = conversation.id;
      _newName = TextEditingController(text: conversation.title)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: conversation.title.length,
        );
    });
  }

  void _endRename() {
    final TextEditingController? controller = _newName;
    setState(() {
      _renaming = null;
      _newName = null;
    });
    controller?.dispose();
  }

  void _commitRename(ConversationId conversationId) {
    final String title = _newName?.text.trim() ?? '';
    final void Function(ConversationId, String)? onRename = widget.onRename;
    _endRename();
    onRename?.call(conversationId, title);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final AppLocalizations words = AppLocalizations.of(context);
    final ValueChanged<String>? onSearch = widget.onSearch;
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
            if (_renaming != null) {
              _endRename();
              return KeyEventResult.handled;
            }
            widget.onClose();
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
                      words.conversationsTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      key: const Key('conversation-new-button'),
                      tooltip: words.newConversation,
                      icon: const Icon(Icons.add_rounded),
                      onPressed: widget.onNew,
                    ),
                    IconButton(
                      key: const Key('conversation-history-close-button'),
                      tooltip: words.closeConversations,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ConversationContentColumn(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (onSearch != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            conversationContentMargin,
                            0,
                            conversationContentMargin,
                            8,
                          ),
                          child: TextField(
                            key: const Key('conversation-search-field'),
                            controller: _search,
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: colors.surfaceContainerHighest,
                              hintText: words.searchConversations,
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 18,
                              ),
                              border: const OutlineInputBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(10),
                                ),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            // Rebuilt here as well as reported outwards: the
                            // empty state has to say "nothing matched" rather
                            // than "nothing yet", and it can only tell the
                            // difference by what is in this field.
                            onChanged: (String query) {
                              // Rebuilt at once so the empty state can say
                              // "nothing matched" rather than "nothing yet",
                              // but the store is only asked once the typing
                              // stops.
                              setState(() {});
                              _searchDebounce?.cancel();
                              _searchDebounce = Timer(
                                _searchQuiet,
                                () => onSearch(query),
                              );
                            },
                          ),
                        ),
                      Expanded(child: _list(context, words, colors)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(
    BuildContext context,
    AppLocalizations words,
    ColorScheme colors,
  ) {
    if (widget.conversations.isEmpty) {
      // "Nothing here yet" and "nothing matched what you typed" are different
      // answers, and answering the second with the first reads as a list that
      // has quietly broken.
      final bool searching = _search.text.trim().isNotEmpty;
      return Padding(
        padding: const EdgeInsets.all(conversationContentMargin),
        child: Text(
          searching ? words.noMatches : words.nothingYet,
          key: Key(
            searching ? 'conversation-no-matches' : 'conversation-nothing-yet',
          ),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: conversationContentMargin,
      ),
      itemCount: widget.conversations.length,
      itemBuilder: (BuildContext context, int index) =>
          _row(context, words, widget.conversations[index]),
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations words,
    ConversationSummary conversation,
  ) {
    final void Function(ConversationId, {required bool pinned})? onPin =
        widget.onPin;
    if (_renaming == conversation.id) {
      return ListTile(
        key: Key('conversation-row-${conversation.id.value}'),
        title: TextField(
          key: const Key('conversation-rename-field'),
          controller: _newName,
          autofocus: true,
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
          ),
          onSubmitted: (String _) => _commitRename(conversation.id),
        ),
        trailing: IconButton(
          key: const Key('conversation-rename-cancel'),
          tooltip: words.reviseCancel,
          icon: const Icon(Icons.close_rounded),
          onPressed: _endRename,
        ),
      );
    }
    return ListTile(
      key: Key('conversation-row-${conversation.id.value}'),
      leading: onPin == null
          ? null
          : IconButton(
              key: Key('conversation-pin-${conversation.id.value}'),
              tooltip: conversation.isPinned
                  ? words.unpinConversation
                  : words.pinConversation,
              icon: Icon(
                conversation.isPinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                size: 18,
              ),
              color: conversation.isPinned
                  ? Theme.of(context).colorScheme.primary
                  : null,
              onPressed: () =>
                  onPin(conversation.id, pinned: !conversation.isPinned),
            ),
      title: Text(
        conversation.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => widget.onOpen(conversation.id),
      // One menu rather than a row of icons: four actions on every row would
      // compete with the conversation the row is for.
      trailing: PopupMenuButton<_RowAction>(
        key: Key('conversation-menu-${conversation.id.value}'),
        tooltip: words.conversationActions,
        icon: const Icon(Icons.more_horiz_rounded),
        itemBuilder: (BuildContext context) => <PopupMenuEntry<_RowAction>>[
          if (widget.onRename != null)
            PopupMenuItem<_RowAction>(
              key: Key('conversation-rename-${conversation.id.value}'),
              value: _RowAction.rename,
              child: Text(words.renameConversation),
            ),
          if (widget.onExport != null)
            PopupMenuItem<_RowAction>(
              key: Key('conversation-export-${conversation.id.value}'),
              value: _RowAction.export,
              child: Text(words.exportConversation),
            ),
          PopupMenuItem<_RowAction>(
            key: Key('conversation-delete-${conversation.id.value}'),
            value: _RowAction.forget,
            child: Text(words.forgetConversation),
          ),
        ],
        onSelected: (_RowAction action) {
          switch (action) {
            case _RowAction.rename:
              _beginRename(conversation);
            case _RowAction.export:
              widget.onExport?.call(conversation.id);
            case _RowAction.forget:
              widget.onDelete(conversation.id);
          }
        },
      ),
    );
  }
}

/// What a row's menu offers.
enum _RowAction {
  /// Give the conversation a name of the user's own.
  rename,

  /// Write it out as Markdown.
  export,

  /// Forget it and every turn in it.
  forget,
}
