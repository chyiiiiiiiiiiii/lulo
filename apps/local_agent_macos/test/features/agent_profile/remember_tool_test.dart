import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/agent_profile/agent_profile_store.dart';
import 'package:local_agent_macos/features/agent_profile/remember_tool.dart';
import 'package:local_agent_macos/features/conversation/conversation_search_tool.dart';

/// A tool over a store nothing else is holding, so each test starts empty.
({RememberTool tool, AgentProfileStore store}) _tool([AgentProfile? profile]) {
  final InMemoryAgentProfileStore store = InMemoryAgentProfileStore(profile);
  addTearDown(store.dispose);
  return (
    tool: RememberTool(profileOf: () => store.current, save: store.save),
    store: store,
  );
}

AgentProfile _withMemories(List<AgentMemory> memories) =>
    AgentProfile(memories: memories);

AgentMemory _memory(int index, String content) => AgentMemory(
  id: 'memory-$index',
  kind: AgentMemoryKind.personal,
  content: content,
);

void main() {
  test('declares the content the model must supply', () {
    final tool = _tool().tool;
    expect(tool.name, 'remember');
    expect(tool.parameters.keys, contains('content'));
  });

  test('can share one toolbox with the tool that is registered', () {
    // It is not registered today — gemma-4-E4B measured 0/5 at calling it,
    // see `the-model-will-not-interrupt-itself-to-remember.md`. This is the
    // guard for the day a model does: `AgentToolbox` throws on a duplicate
    // name and the app builds it lazily, so the collision would otherwise
    // first surface on the user's machine when a model was created.
    final AgentToolbox box = AgentToolbox(<AgentTool>[
      ConversationSearchTool(searchConversations: (_) async => []),
      _tool().tool,
    ]);
    expect(box.declarationsJson, contains('remember'));
    expect(box.declarationsJson, contains('search_conversations'));
  });

  test('keeps the fact where the next turn will read it', () async {
    final (:RememberTool tool, :AgentProfileStore store) = _tool();

    final result =
        await tool.call(<String, Object?>{'content': '使用者住在台北'})
            as Map<String, Object?>;

    expect(result['status'], 'saved');
    expect(store.current.memories.single.content, '使用者住在台北');
    // The point of the whole feature: a question asked afterwards carries it.
    expect(
      composeAgentPrompt(
        profile: store.current,
        prompt: '今天要帶傘嗎',
      ).turnInstruction,
      contains('使用者住在台北'),
    );
  });

  test('the same fact twice is not two rows', () async {
    final (:RememberTool tool, :AgentProfileStore store) = _tool();
    await tool.call(<String, Object?>{'content': '使用者住在台北'});

    // Case-folded and trimmed, because the model rewrites its own sentences.
    final result =
        await tool.call(<String, Object?>{'content': '  使用者住在台北  '})
            as Map<String, Object?>;

    expect(result['status'], 'already_known');
    expect(result['id'], 'memory-1');
    expect(store.current.memories, hasLength(1));
  });

  test(
    'a triggerless project memory is stored as one that can be recalled',
    () async {
      final (:RememberTool tool, :AgentProfileStore store) = _tool();

      final result =
          await tool.call(<String, Object?>{
                'content': '使用者在做 Lulo 這個桌面助手',
                'kind': 'project',
              })
              as Map<String, Object?>;

      // Stored as asked it would never be selected, so it is never stored as
      // asked: `selectAgentMemories` only lets a triggerless memory through
      // when it is personal or a preference.
      expect(result['kind'], 'personal');
      expect(
        selectAgentMemories(profile: store.current, prompt: '早安').memories,
        hasLength(1),
      );
    },
  );

  test('triggers keep the kind the model chose', () async {
    final (:RememberTool tool, :AgentProfileStore store) = _tool();

    final result =
        await tool.call(<String, Object?>{
              'content': '使用者在做 Lulo 這個桌面助手',
              'kind': 'project',
              'triggers': <Object?>['Lulo', '  ', 42],
            })
            as Map<String, Object?>;

    expect(result['kind'], 'project');
    final AgentMemory saved = store.current.memories.single;
    expect(saved.triggers, <String>['Lulo']);
    expect(
      selectAgentMemories(profile: store.current, prompt: '早安').memories,
      isEmpty,
    );
    expect(
      selectAgentMemories(
        profile: store.current,
        prompt: 'Lulo 現在做到哪',
      ).memories,
      hasLength(1),
    );
  });

  test('a preference stays a preference without triggers', () async {
    final (:RememberTool tool, :AgentProfileStore store) = _tool();

    await tool.call(<String, Object?>{
      'content': '使用者希望回答短一點',
      'kind': 'preference',
    });

    expect(store.current.memories.single.kind, AgentMemoryKind.preference);
  });

  test('missing content is an error the model can read, not a crash', () async {
    final (:RememberTool tool, :AgentProfileStore store) = _tool();
    final result = await tool.call(const <String, Object?>{});
    expect((result! as Map<String, Object?>)['error'], isNotEmpty);
    expect(store.current.memories, isEmpty);
  });

  test('a fact longer than the prompt budget affords is refused', () async {
    final (:RememberTool tool, :AgentProfileStore store) = _tool();

    final result =
        await tool.call(<String, Object?>{
              'content': '使' * (RememberTool.maxContentCharacters + 1),
            })
            as Map<String, Object?>;

    expect(result['error'], contains('${RememberTool.maxContentCharacters}'));
    expect(store.current.memories, isEmpty);
  });

  test('a full list stops adding rather than dropping the oldest', () async {
    final AgentProfile full = _withMemories(<AgentMemory>[
      for (int i = 1; i <= RememberTool.maxMemories; i += 1)
        _memory(i, '事實 $i'),
    ]);
    final (:RememberTool tool, :AgentProfileStore store) = _tool(full);

    final result =
        await tool.call(<String, Object?>{'content': '一件新的事'})
            as Map<String, Object?>;

    expect(result['error'], isNotEmpty);
    expect(store.current.memories, hasLength(RememberTool.maxMemories));
    expect(store.current.memories.first.content, '事實 1');
  });

  test('the id never collides with one the settings sheet wrote', () async {
    final (:RememberTool tool, :AgentProfileStore store) = _tool(
      _withMemories(<AgentMemory>[_memory(1, '甲'), _memory(2, '乙')]),
    );

    await tool.call(<String, Object?>{'content': '丙'});

    expect(store.current.memories.last.id, 'memory-3');
    expect(
      store.current.memories.map((AgentMemory m) => m.id).toSet(),
      hasLength(3),
    );
  });

  test('a correction supersedes the fact it makes wrong', () async {
    // The reason `replaces` is declared to the model at all. Kept without
    // it, both facts are triggerless personal memories and both land in the
    // same prompt — the agent is told the user lives in two cities.
    final (:RememberTool tool, :AgentProfileStore store) = _tool(
      _withMemories(<AgentMemory>[_memory(1, '使用者住在台北')]),
    );

    final result =
        await tool.call(<String, Object?>{
              'content': '使用者搬到台南了',
              'replaces': <Object?>['memory-1'],
            })
            as Map<String, Object?>;

    expect(result['status'], 'saved');
    expect(result['replaced'], <String>['memory-1']);
    expect(store.current.memories.single.content, '使用者搬到台南了');
  });

  test('an id nothing owns is said out loud, not silently obeyed', () async {
    final (:RememberTool tool, :AgentProfileStore store) = _tool();

    final result =
        await tool.call(<String, Object?>{
              'content': '使用者住在台南',
              'replaces': <Object?>['memory-7'],
            })
            as Map<String, Object?>;

    // The fact still lands — losing it as well would be two failures for
    // one wrong argument.
    expect(result['status'], 'saved');
    expect(result['note'], contains('memory-7'));
    expect(store.current.memories, hasLength(1));
  });

  test('everything else in the profile survives a save', () async {
    final (:RememberTool tool, :AgentProfileStore store) = _tool(
      AgentProfile(
        identity: const AgentIdentity(userName: '阿一'),
        misheard: <MisheardWord>[
          const MisheardWord(heard: '路落', meant: 'Lulo'),
        ],
        additionalInstructions: const <String>['別用表情符號。'],
      ),
    );

    await tool.call(<String, Object?>{'content': '使用者住在台北'});

    expect(store.current.identity.userName, '阿一');
    expect(store.current.misheard, hasLength(1));
    expect(store.current.additionalInstructions, <String>['別用表情符號。']);
  });
}
