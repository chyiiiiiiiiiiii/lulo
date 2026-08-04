import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  test('the built-in profile knows the words this app is about', () {
    // These reach two places that both need them and neither of which can
    // invent them: the recogniser biases towards them, and the transcript
    // refiner refuses to edit them away. Left empty, they came only from a
    // profile file on one developer's disk — so the check for them passed
    // there and could never pass anywhere else.
    expect(
      AgentProfile.builtIn().vocabulary,
      containsAll(<String>['Lulo', 'Flutter', 'Gemma', 'Qwen']),
    );
  });

  test(
    'the built-in profile speaks as Lulo in Taiwanese Traditional Chinese',
    () {
      final AgentProfile profile = AgentProfile.builtIn();

      expect(profile.schemaVersion, 1);
      expect(profile.identity.agentName, 'Lulo');
      expect(profile.identity.locale, 'zh-TW');
      expect(profile.personality.responseLength, AgentResponseLength.concise);
      expect(profile.personality.admitUncertainty, isTrue);
      expect(profile.personality.leadWithAnswer, isTrue);
      expect(profile.voiceBehavior.avoidMarkdown, isTrue);
      expect(profile.voiceBehavior.avoidReadingUrls, isTrue);
      expect(profile.voiceBehavior.avoidLongLists, isTrue);
      expect(profile.voiceBehavior.preferNaturalShortSentences, isTrue);
    },
  );

  test('profile collections cannot be changed after construction', () {
    final List<AgentMemory> memories = <AgentMemory>[
      AgentMemory(
        id: 'project-lulo',
        kind: AgentMemoryKind.project,
        content: '正在開發 Lulo。',
        triggers: <String>['Lulo'],
      ),
    ];
    final List<String> vocabulary = <String>['Flutter'];
    final AgentProfile profile = AgentProfile(
      memories: memories,
      vocabulary: vocabulary,
    );

    memories.clear();
    vocabulary.clear();

    expect(profile.memories, hasLength(1));
    expect(profile.vocabulary, <String>['Flutter']);
    expect(
      () => profile.memories.add(profile.memories.single),
      throwsUnsupportedError,
    );
    expect(() => profile.vocabulary.add('MLX'), throwsUnsupportedError);
  });

  test('a memory rejects an empty stable id', () {
    expect(
      () => AgentMemory(
        id: '  ',
        kind: AgentMemoryKind.preference,
        content: '偏好簡短回答。',
      ),
      throwsArgumentError,
    );
  });

  test('a memory rejects empty content', () {
    expect(
      () => AgentMemory(
        id: 'answer-length',
        kind: AgentMemoryKind.preference,
        content: '\n',
      ),
      throwsArgumentError,
    );
  });

  test('equal profile values compare equal', () {
    final AgentProfile first = AgentProfile(
      identity: const AgentIdentity(userName: 'Yii'),
      memories: <AgentMemory>[
        AgentMemory(
          id: 'project-lulo',
          kind: AgentMemoryKind.project,
          content: '正在開發 Lulo。',
          triggers: <String>['Lulo'],
        ),
      ],
    );
    final AgentProfile second = AgentProfile(
      identity: const AgentIdentity(userName: 'Yii'),
      memories: <AgentMemory>[
        AgentMemory(
          id: 'project-lulo',
          kind: AgentMemoryKind.project,
          content: '正在開發 Lulo。',
          triggers: <String>['Lulo'],
        ),
      ],
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });
}
