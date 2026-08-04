import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  test('the stable profile separates from what this turn contributes', () {
    final AgentProfile profile = AgentProfile(
      identity: const AgentIdentity(userName: 'Yii'),
      additionalInstructions: <String>['回答時可以更有個性。'],
      memories: <AgentMemory>[
        AgentMemory(
          id: 'lulo',
          kind: AgentMemoryKind.project,
          content: 'Yii 正在開發 Lulo。',
          triggers: const <String>['Lulo'],
        ),
      ],
    );

    final AgentPromptContext result = composeAgentPrompt(
      profile: profile,
      prompt: 'Lulo 下一步怎麼做？',
    );

    // What the model is told about who it is does not change between turns,
    // so it can be prefilled once instead of re-read with every question.
    expect(result.systemInstruction, contains('[核心人格]'));
    expect(result.systemInstruction, contains('[語音回答方式]'));
    expect(result.systemInstruction, contains('[使用者偏好]'));
    expect(result.systemInstruction, contains('[開發者額外指示]'));
    expect(result.systemInstruction, isNot(contains('Lulo 下一步怎麼做？')));
    expect(result.systemInstruction, isNot(contains('[問題]')));

    // What this question drags in with it does change, and stays with it.
    expect(result.turnInstruction, contains('[與這次問題相關的記憶]'));
    expect(result.turnInstruction, contains('Yii 正在開發 Lulo。'));
    expect(result.turnInstruction, endsWith('[問題]\nLulo 下一步怎麼做？'));

    expect(
      result.instruction,
      '${result.systemInstruction}\n\n${result.turnInstruction}',
    );
  });

  test('a turn with no relevant memory contributes only its question', () {
    final AgentPromptContext result = composeAgentPrompt(
      profile: AgentProfile.builtIn(),
      prompt: '你好',
    );

    expect(result.turnInstruction, '[問題]\n你好');
  });

  test('the stable profile is identical for two questions in one language', () {
    final AgentProfile profile = AgentProfile(
      identity: const AgentIdentity(userName: 'Yii'),
    );

    final AgentPromptContext first = composeAgentPrompt(
      profile: profile,
      prompt: '今天天氣如何？',
    );
    final AgentPromptContext second = composeAgentPrompt(
      profile: profile,
      prompt: '那明天呢？',
    );

    // The whole point: an unchanged system instruction is a KV cache the
    // next turn does not have to pay for again.
    expect(second.systemInstruction, first.systemInstruction);
  });

  test('Chinese context keeps sections ordered and asks the question once', () {
    final AgentProfile profile = AgentProfile(
      identity: const AgentIdentity(userName: 'Yii'),
      memories: <AgentMemory>[
        AgentMemory(
          id: 'lulo',
          kind: AgentMemoryKind.project,
          content: 'Yii 正在開發 Lulo。',
          triggers: const <String>['Lulo'],
        ),
        AgentMemory(
          id: 'other',
          kind: AgentMemoryKind.project,
          content: '這次不相關。',
          triggers: const <String>['Moniit'],
        ),
      ],
    );

    final AgentPromptContext result = composeAgentPrompt(
      profile: profile,
      prompt: 'Lulo 下一步怎麼做？',
    );

    expect(result.selectedMemoryIds, <String>['lulo']);
    expect(result.instruction, contains('[核心人格]'));
    expect(result.instruction, contains('[語音回答方式]'));
    expect(result.instruction, contains('[使用者偏好]'));
    expect(result.instruction, contains('[與這次問題相關的記憶]'));
    expect(result.instruction, isNot(contains('這次不相關')));
    expect(result.instruction, contains('用臺灣繁體中文回答'));
    expect('Lulo 下一步怎麼做？'.allMatches(result.instruction), hasLength(1));
    expect(
      result.instruction.indexOf('[核心人格]'),
      lessThan(result.instruction.indexOf('[語音回答方式]')),
    );
    expect(
      result.instruction.indexOf('[語音回答方式]'),
      lessThan(result.instruction.indexOf('[使用者偏好]')),
    );
    expect('[使用者偏好]'.allMatches(result.instruction), hasLength(1));
  });

  test('English questions receive English behavior instructions', () {
    final AgentPromptContext result = composeAgentPrompt(
      profile: AgentProfile.builtIn(),
      prompt: 'What should I do next?',
    );

    expect(result.instruction, contains('Answer in natural spoken English'));
    expect(result.instruction, isNot(contains('用臺灣繁體中文回答')));
  });

  test('empty optional sections are omitted', () {
    final AgentPromptContext result = composeAgentPrompt(
      profile: AgentProfile.builtIn(),
      prompt: '你好',
    );

    expect(result.instruction, isNot(contains('[與這次問題相關的記憶]')));
    expect(result.instruction, isNot(contains('[開發者額外指示]')));
  });

  test('built-in honesty and spoken-prose rules survive custom content', () {
    final AgentProfile profile = AgentProfile(
      additionalInstructions: <String>['回答時可以更有個性。'],
    );

    final AgentPromptContext result = composeAgentPrompt(
      profile: profile,
      prompt: '介紹你自己',
    );

    expect(result.instruction, contains('不確定時坦白說明'));
    expect(result.instruction, contains('不要使用 Markdown'));
    expect(result.instruction, contains('回答時可以更有個性'));
  });

  test('profile content stays bounded while the question remains complete', () {
    final AgentProfile profile = AgentProfile(
      memories: <AgentMemory>[
        for (int index = 0; index < 6; index += 1)
          AgentMemory(
            id: 'm$index',
            kind: AgentMemoryKind.preference,
            content: List<String>.filled(80, '$index').join(),
          ),
      ],
      additionalInstructions: <String>[
        List<String>.filled(600, '額').join(),
        '這一條應該先被截去',
      ],
    );

    final AgentPromptContext result = composeAgentPrompt(
      profile: profile,
      prompt: '完整問題不可被截斷',
      maxProfileCharacters: 520,
    );

    expect(result.profileCharacterCount, lessThanOrEqualTo(520));
    expect(result.instruction, endsWith('[問題]\n完整問題不可被截斷'));
    expect(result.instruction, isNot(contains('額額額額額額額額額額額額額額額額額額額額')));
    expect(result.instruction, contains('不確定時坦白說明'));
  });
}
