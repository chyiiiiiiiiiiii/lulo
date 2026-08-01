import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  AgentMemory memory(
    String id,
    AgentMemoryKind kind,
    String content, {
    List<String> triggers = const <String>[],
    bool enabled = true,
  }) => AgentMemory(
    id: id,
    kind: kind,
    content: content,
    triggers: triggers,
    enabled: enabled,
  );

  test('disabled and unrelated memories never enter the selection', () {
    final AgentProfile profile = AgentProfile(
      memories: <AgentMemory>[
        memory('disabled', AgentMemoryKind.personal, '不該出現', enabled: false),
        memory(
          'other',
          AgentMemoryKind.project,
          'Moniit',
          triggers: <String>['Moniit'],
        ),
        memory(
          'lulo',
          AgentMemoryKind.project,
          'Lulo 專案',
          triggers: <String>['Lulo'],
        ),
      ],
    );

    final AgentMemorySelection result = selectAgentMemories(
      profile: profile,
      prompt: '繼續處理 Lulo',
    );

    expect(result.memories.map((AgentMemory item) => item.id), <String>[
      'lulo',
    ]);
  });

  test('triggerless personal and preference memories are always eligible', () {
    final AgentProfile profile = AgentProfile(
      memories: <AgentMemory>[
        memory('name', AgentMemoryKind.personal, '稱呼 Yii'),
        memory('brief', AgentMemoryKind.preference, '偏好簡短回答'),
        memory('project', AgentMemoryKind.project, '沒有 trigger 的專案'),
      ],
    );

    final AgentMemorySelection result = selectAgentMemories(
      profile: profile,
      prompt: '今天天氣如何',
    );

    expect(result.memories.map((AgentMemory item) => item.id), <String>[
      'name',
      'brief',
    ]);
  });

  test('Latin triggers ignore case and Chinese triggers match substrings', () {
    final AgentProfile profile = AgentProfile(
      memories: <AgentMemory>[
        memory(
          'flutter',
          AgentMemoryKind.vocabulary,
          'Flutter',
          triggers: <String>['FLUTTER'],
        ),
        memory(
          'agent',
          AgentMemoryKind.project,
          '地端 Agent',
          triggers: <String>['地端 Agent'],
        ),
      ],
    );

    expect(
      selectAgentMemories(profile: profile, prompt: 'flutter 的架構').memoryIds,
      <String>['flutter'],
    );
    expect(
      selectAgentMemories(profile: profile, prompt: '我的地端 Agent').memoryIds,
      <String>['agent'],
    );
  });

  test('matched memories lead and longer triggers lead shorter triggers', () {
    final AgentProfile profile = AgentProfile(
      memories: <AgentMemory>[
        memory('always', AgentMemoryKind.preference, '永遠符合'),
        memory(
          'short',
          AgentMemoryKind.project,
          '短',
          triggers: <String>['Agent'],
        ),
        memory(
          'long',
          AgentMemoryKind.project,
          '長',
          triggers: <String>['地端 Agent'],
        ),
      ],
    );

    expect(
      selectAgentMemories(profile: profile, prompt: '地端 Agent').memoryIds,
      <String>['long', 'short', 'always'],
    );
  });

  test('ties preserve file order and duplicate content appears once', () {
    final AgentProfile profile = AgentProfile(
      memories: <AgentMemory>[
        memory(
          'first',
          AgentMemoryKind.project,
          '同一件事',
          triggers: <String>['Lulo'],
        ),
        memory(
          'second',
          AgentMemoryKind.project,
          '另一件事',
          triggers: <String>['Lulo'],
        ),
        memory('duplicate', AgentMemoryKind.preference, '同一件事'),
      ],
    );

    expect(
      selectAgentMemories(profile: profile, prompt: 'Lulo').memoryIds,
      <String>['first', 'second'],
    );
  });

  test('selection accepts at most six complete memories', () {
    final AgentProfile profile = AgentProfile(
      memories: <AgentMemory>[
        for (int index = 0; index < 8; index += 1)
          memory('m$index', AgentMemoryKind.preference, 'memory-$index'),
      ],
    );

    final AgentMemorySelection result = selectAgentMemories(
      profile: profile,
      prompt: 'anything',
    );

    expect(result.memories, hasLength(6));
    expect(result.characterCount, 48);
  });

  test('character bound never cuts a memory in half', () {
    final AgentProfile profile = AgentProfile(
      memories: <AgentMemory>[
        memory('first', AgentMemoryKind.preference, '1234'),
        memory('too-long', AgentMemoryKind.preference, '56789'),
        memory('fits', AgentMemoryKind.preference, 'ab'),
      ],
    );

    final AgentMemorySelection result = selectAgentMemories(
      profile: profile,
      prompt: 'anything',
      maxCharacters: 6,
    );

    expect(result.memoryIds, <String>['first', 'fits']);
    expect(result.characterCount, 6);
  });
}
