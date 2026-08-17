import 'package:agent_core/agent_core.dart';

/// Keeps one fact about the user past the end of a conversation.
///
/// The write half the memories list never had: the field existed and the
/// composer read it, but only a person typing into Settings ever filled it,
/// so every conversation started from nothing the user had already said.
///
/// **Not registered in the toolbox, and not because it is unfinished.**
/// gemma-4-E4B does not call it — 0/5 across eleven conditions, including
/// the one where the user says 「記住我住在台南」 outright, while
/// `ConversationSearchTool` fires 5/5 in the same toolbox on the same turn.
/// Asked to remember, the model answers 「我記住了」 and writes nothing. A
/// tool call is a decision to interrupt the answer for something needed to
/// answer, and a fact the user just said is already in the window. The
/// measurement, the control that makes it mean something, and the
/// second-pass design that scores 15/15 instead are in
/// `docs/decisions/the-model-will-not-interrupt-itself-to-remember.md`.
///
/// What survives that is everything below: this is the bounded write path,
/// and the second pass will call it. It writes into `agent_profile.json` —
/// the same file the settings sheet edits — which is why it needs no
/// permission layer. Every entry it writes is a row on that sheet with a
/// switch and a forget button, and nothing here can write anywhere else.
///
/// The bounds are the point. A memory is not free — each one spends from the
/// 1200-character profile budget in `composeAgentPrompt`, ahead of the
/// question — so this caps the length of one, caps how many exist, and
/// refuses to write the same fact twice.
final class RememberTool implements AgentTool {
  /// Creates the tool over exactly the two capabilities it uses.
  ///
  /// Functions rather than the store, for the reason `ConversationSearchTool`
  /// takes a search function: a test needs a profile and somewhere to put
  /// one, not a file watcher.
  RememberTool({
    required AgentProfile Function() profileOf,
    required Future<void> Function(AgentProfile profile) save,
  }) : _profile = profileOf,
       _write = save;

  final AgentProfile Function() _profile;
  final Future<void> Function(AgentProfile) _write;

  /// The longest fact worth keeping, and the most that may be kept.
  ///
  /// Both are `writeAgentMemory`'s, named here so a caller reading the tool
  /// does not have to go and find them. Bounds belong to the write path
  /// rather than to whoever calls it: the second pass has to be held to the
  /// same 1200-character prompt budget as this is, and a second copy of
  /// these numbers is how the two would come to disagree.
  static const int maxContentCharacters = maxAgentMemoryCharacters;

  /// See [maxContentCharacters].
  static const int maxMemories = maxAgentMemories;

  @override
  String get name => 'remember';

  @override
  String get description =>
      'Saves one durable fact about the user so you still know it in future '
      'conversations. Use it when the user tells you something about '
      'themselves, states a preference for how you should answer, or '
      'describes a project they are working on — not for anything that is '
      'only true for this conversation, and not for what you can already '
      'see in the conversation. Keep the fact to one short sentence, '
      'written from your point of view about the user.';

  @override
  Map<String, Object?> get parameters => const <String, Object?>{
    'content': <String, Object?>{
      'type': 'string',
      'description':
          'The fact to keep, as one short sentence in the language the '
          'user said it in.',
    },
    'kind': <String, Object?>{
      'type': 'string',
      'enum': <String>['personal', 'preference', 'project', 'vocabulary'],
      'description':
          'personal for a stable fact about the user, preference for how '
          'they want you to answer, project for an ongoing body of work, '
          'vocabulary for a term whose spelling should stay fixed.',
    },
    'triggers': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'type': 'string'},
      'description':
          'Words that should bring this fact back. Leave empty for a fact '
          'that is always worth knowing; supply them for a project or a '
          'term, which is only recalled when one of these words appears.',
    },
    'replaces': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'type': 'string'},
      'description':
          'Ids of memories this fact makes wrong, which are deleted. Use it '
          'whenever the user corrects or updates something you already know '
          '— a profile that keeps both the old fact and the new one will '
          'tell you both.',
    },
  };

  @override
  Future<Object?> call(Map<String, Object?> arguments) async {
    final Object? raw = arguments['content'];
    if (raw is! String) {
      // Written for the model to read and retry, the same way
      // `search_conversations` answers a missing query: the arguments came
      // from the model, and the turn has to survive them.
      return const <String, Object?>{
        'error': 'content is required: the one sentence to remember.',
      };
    }
    final AgentProfile profile = _profile();
    final AgentMemoryWriteResult write = writeAgentMemory(
      profile: profile,
      content: raw,
      kind:
          AgentMemoryKind.values.asNameMap()[arguments['kind']] ??
          AgentMemoryKind.personal,
      triggers: _strings(arguments['triggers']),
      replaces: _strings(arguments['replaces']),
      maxCharacters: maxContentCharacters,
      maxMemories: maxMemories,
    );
    switch (write.status) {
      case AgentMemoryWriteStatus.rejected:
        return <String, Object?>{'error': write.error};
      case AgentMemoryWriteStatus.refused:
        // Said plainly and without repeating the content back. The model
        // wrote the argument, so quoting it into the answer is how a
        // password refused by the screen ends up spoken aloud instead.
        return <String, Object?>{
          'error': switch (write.refusal!) {
            AgentMemoryRefusal.instruction =>
              'That reads as an instruction rather than a fact about the '
                  'user, and was not saved.',
            AgentMemoryRefusal.secret =>
              'That looks like a secret. It was not saved, and should not '
                  'be repeated back.',
          },
        };
      case AgentMemoryWriteStatus.unchanged:
        // Not an error: nothing went wrong, the profile simply already said
        // this. Saying so twice reads to the user as an agent that was not
        // listening the first time.
        return <String, Object?>{'status': 'already_known', 'id': write.id};
      case AgentMemoryWriteStatus.saved:
        await _write(profile.copyWith(memories: write.memories));
        return <String, Object?>{
          'status': 'saved',
          'id': write.id,
          // The kind it was stored under, which is not always the one asked
          // for: a triggerless project becomes personal or it could never be
          // recalled. Reporting the request back would tell the model it
          // saved something it did not.
          'kind': write.kind?.name,
          if (write.replacedIds.isNotEmpty) 'replaced': write.replacedIds,
          if (write.unknownReplaceIds.isNotEmpty)
            'note':
                'No memory has the id '
                '${write.unknownReplaceIds.join(", ")}; nothing was '
                'replaced under it.',
        };
    }
  }

  static List<String> _strings(Object? value) => <String>[
    if (value is List<Object?>)
      for (final Object? entry in value)
        if (entry is String) entry,
  ];
}
