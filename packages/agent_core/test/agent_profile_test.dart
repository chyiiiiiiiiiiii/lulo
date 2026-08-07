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

  group('changing one part of the profile', () {
    test('leaves every other part exactly as it was', () {
      // Settings shows some of the profile and the file holds all of it. Any
      // edit made from the app rebuilds the whole value, so a copy that
      // dropped what it was not given would strip the recogniser's own
      // vocabulary the first time the user typed their name.
      final AgentProfile original = AgentProfile(
        identity: const AgentIdentity(agentName: 'Lulo', userName: 'Yii'),
        turnTaking: const TurnTakingWords(acknowledgements: <String>['蛤']),
        memories: <AgentMemory>[
          AgentMemory(
            id: 'home',
            kind: AgentMemoryKind.personal,
            content: '住在台中',
          ),
        ],
        vocabulary: <String>['Lulo', 'LiteRT'],
        additionalInstructions: <String>['用繁體中文'],
      );

      final AgentProfile renamed = original.copyWith(
        identity: const AgentIdentity(agentName: '露露', userName: 'Yii'),
      );

      expect(renamed.identity.agentName, '露露');
      expect(renamed.turnTaking, original.turnTaking);
      expect(renamed.memories, original.memories);
      expect(renamed.vocabulary, original.vocabulary);
      expect(renamed.additionalInstructions, original.additionalInstructions);
      expect(renamed.voiceBehavior, original.voiceBehavior);
      expect(renamed.personality, original.personality);
    });

    test('rebuilds who has the floor from the new words', () {
      // floorControl is derived rather than stored, so a copy that carried
      // the old one over would save the word and keep ignoring it.
      final AgentProfile original = AgentProfile();
      expect(
        original.floorControl.classify('蛤'),
        isNot(FloorClaim.backchannel),
      );

      final AgentProfile listening = original.copyWith(
        turnTaking: const TurnTakingWords(acknowledgements: <String>['蛤']),
      );

      expect(listening.floorControl.classify('蛤'), FloorClaim.backchannel);
    });
  });
}
