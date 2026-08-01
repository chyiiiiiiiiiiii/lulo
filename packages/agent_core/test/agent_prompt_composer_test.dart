import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
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
    expect(result.instruction, isNot(contains('這一條應該先被截去')));
    expect(result.instruction, contains('不確定時坦白說明'));
  });
}
