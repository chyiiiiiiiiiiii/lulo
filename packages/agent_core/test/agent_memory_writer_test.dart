import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

AgentMemory _memory(
  String id,
  String content, {
  AgentMemoryKind kind = AgentMemoryKind.personal,
  List<String> triggers = const <String>[],
}) => AgentMemory(id: id, kind: kind, content: content, triggers: triggers);

AgentProfile _profile(List<AgentMemory> memories) =>
    AgentProfile(memories: memories);

List<String> _contents(AgentMemoryWriteResult result) => <String>[
  for (final AgentMemory memory in result.memories) memory.content,
];

void main() {
  test('a first fact is appended and reported under its new id', () {
    final AgentMemoryWriteResult result = writeAgentMemory(
      profile: _profile(const <AgentMemory>[]),
      content: '  使用者住在台北。  ',
    );

    expect(result.status, AgentMemoryWriteStatus.saved);
    expect(result.id, 'memory-1');
    expect(result.memories.single.content, '使用者住在台北。');
    expect(result.replacedIds, isEmpty);
  });

  test('a fact that supersedes another leaves only the new one', () {
    // The failure this whole function exists for. Both are triggerless
    // personal memories, so without the replacement both are eligible for
    // the same turn and the model is handed two contradictory facts.
    final AgentProfile profile = _profile(<AgentMemory>[
      _memory('memory-1', '使用者住在台北'),
      _memory('memory-2', '使用者喜歡短一點的回答'),
    ]);

    final AgentMemoryWriteResult result = writeAgentMemory(
      profile: profile,
      content: '使用者搬到台南了',
      replaces: <String>['memory-1'],
    );

    expect(result.status, AgentMemoryWriteStatus.saved);
    expect(result.replacedIds, <String>['memory-1']);
    expect(_contents(result), <String>['使用者喜歡短一點的回答', '使用者搬到台南了']);
    expect(
      selectAgentMemories(
        profile: _profile(result.memories),
        prompt: '早安',
      ).memories.map((AgentMemory m) => m.content),
      isNot(contains('使用者住在台北')),
    );
  });

  test('a superseded id is never handed to what superseded it', () {
    // The profile file is something a person opens and reads. Reusing the
    // id would make it say that `memory-2` is a fact `memory-2` replaced.
    final AgentMemoryWriteResult result = writeAgentMemory(
      profile: _profile(<AgentMemory>[
        _memory('memory-1', '甲'),
        _memory('memory-2', '乙'),
      ]),
      content: '丙',
      replaces: <String>['memory-2'],
    );

    expect(result.id, 'memory-3');
    expect(_contents(result), <String>['甲', '丙']);
  });

  test('the same sentence written again changes nothing', () {
    final AgentProfile profile = _profile(<AgentMemory>[
      _memory('memory-1', '使用者搬到台南了。'),
    ]);

    // Case, spaces and a trailing full stop are the ways one model rewrites
    // its own sentence between turns; none of them is a second fact.
    for (final String again in <String>[
      '使用者搬到台南了。',
      '使用者搬到台南了',
      ' 使用者搬到台南了 。 ',
    ]) {
      final AgentMemoryWriteResult result = writeAgentMemory(
        profile: profile,
        content: again,
      );
      expect(result.status, AgentMemoryWriteStatus.unchanged, reason: again);
      expect(result.id, 'memory-1', reason: again);
      expect(result.memories, hasLength(1), reason: again);
    }
  });

  test('a rewrite that is not the same sentence is left to the caller', () {
    // 「使用者搬到了台南」 against 「使用者搬到台南了」 is one fact written twice,
    // and this deliberately does not catch it: the same crude similarity
    // that catches it also catches 「使用者住在台北」, which is the opposite
    // of a duplicate. The judgement belongs to the second pass.
    final AgentMemoryWriteResult result = writeAgentMemory(
      profile: _profile(<AgentMemory>[_memory('memory-1', '使用者搬到台南了')]),
      content: '使用者搬到了台南',
    );

    expect(result.status, AgentMemoryWriteStatus.saved);
    expect(result.memories, hasLength(2));
  });

  test('a known fact still applies the supersession asked for', () {
    final AgentMemoryWriteResult result = writeAgentMemory(
      profile: _profile(<AgentMemory>[
        _memory('memory-1', '使用者住在台北'),
        _memory('memory-2', '使用者搬到台南了'),
      ]),
      content: '使用者搬到台南了',
      replaces: <String>['memory-1'],
    );

    expect(result.status, AgentMemoryWriteStatus.saved);
    expect(result.id, 'memory-2');
    expect(_contents(result), <String>['使用者搬到台南了']);
  });

  test('an id nothing owns is reported and does not lose the fact', () {
    final AgentMemoryWriteResult result = writeAgentMemory(
      profile: _profile(<AgentMemory>[_memory('memory-1', '甲')]),
      content: '乙',
      replaces: <String>['memory-9', 'memory-1'],
    );

    expect(result.status, AgentMemoryWriteStatus.saved);
    expect(result.unknownReplaceIds, <String>['memory-9']);
    expect(result.replacedIds, <String>['memory-1']);
    expect(_contents(result), <String>['乙']);
  });

  test('a full list still accepts a correction', () {
    // The bug this pins: a ceiling that blocks replacement makes the list
    // unfixable exactly when it is most full of things worth fixing.
    final AgentProfile full = _profile(<AgentMemory>[
      for (int i = 1; i <= maxAgentMemories; i += 1)
        _memory('memory-$i', '事實 $i'),
    ]);

    final AgentMemoryWriteResult blocked = writeAgentMemory(
      profile: full,
      content: '一件新的事',
    );
    expect(blocked.status, AgentMemoryWriteStatus.rejected);
    expect(blocked.memories, hasLength(maxAgentMemories));

    final AgentMemoryWriteResult corrected = writeAgentMemory(
      profile: full,
      content: '事實 1 其實不對',
      replaces: <String>['memory-1'],
    );
    expect(corrected.status, AgentMemoryWriteStatus.saved);
    expect(corrected.memories, hasLength(maxAgentMemories));
    expect(_contents(corrected), isNot(contains('事實 1')));
  });

  test('an empty fact and an overlong one are both refused', () {
    final AgentProfile profile = _profile(const <AgentMemory>[]);

    expect(
      writeAgentMemory(profile: profile, content: '   ').status,
      AgentMemoryWriteStatus.rejected,
    );
    final AgentMemoryWriteResult long = writeAgentMemory(
      profile: profile,
      content: '使' * (maxAgentMemoryCharacters + 1),
    );
    expect(long.status, AgentMemoryWriteStatus.rejected);
    expect(long.error, contains('$maxAgentMemoryCharacters'));
    expect(long.memories, isEmpty);
  });

  test('a triggerless memory is stored as a kind that can be recalled', () {
    final AgentMemoryWriteResult result = writeAgentMemory(
      profile: _profile(const <AgentMemory>[]),
      content: '使用者在做 Lulo',
      kind: AgentMemoryKind.project,
    );

    expect(result.memories.single.kind, AgentMemoryKind.personal);
    expect(
      selectAgentMemories(
        profile: _profile(result.memories),
        prompt: '早安',
      ).memories,
      hasLength(1),
    );
  });

  test('triggers keep the kind, and blank ones are dropped', () {
    final AgentMemoryWriteResult result = writeAgentMemory(
      profile: _profile(const <AgentMemory>[]),
      content: '使用者在做 Lulo',
      kind: AgentMemoryKind.project,
      triggers: <String>['Lulo', '   '],
    );

    final AgentMemory saved = result.memories.single;
    expect(saved.kind, AgentMemoryKind.project);
    expect(saved.triggers, <String>['Lulo']);
  });

  test('a preference keeps its kind without triggers', () {
    expect(
      writeAgentMemory(
        profile: _profile(const <AgentMemory>[]),
        content: '使用者希望回答短一點',
        kind: AgentMemoryKind.preference,
      ).memories.single.kind,
      AgentMemoryKind.preference,
    );
  });

  test('a rejected write hands back a list the caller can save blindly', () {
    // Every caller writes `profile.copyWith(memories: result.memories)`
    // without branching, so a refusal has to be the list unchanged rather
    // than an empty one.
    final AgentProfile profile = _profile(<AgentMemory>[
      _memory('memory-1', '甲'),
    ]);
    final AgentMemoryWriteResult result = writeAgentMemory(
      profile: profile,
      content: '',
    );

    expect(result.status, AgentMemoryWriteStatus.rejected);
    expect(_contents(result), <String>['甲']);
  });
}
