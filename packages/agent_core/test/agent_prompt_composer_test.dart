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

  test('the first sentence has to be the answer, not a preamble', () {
    // 「先回答核心」 was not enough of an instruction. Measured against the
    // real model over five questions built to provoke a preamble, only one
    // answer in five opened with the answer; the rest opened with 「兩者不
    // 一樣」, 「原因比較多樣化」, 「這取決於」 — sentences that restate the
    // question. Saying it plainly moved it to four in five.
    //
    // This matters more for speech than for text. A long answer is fine to
    // hear if the first five seconds carried it and barge-in works, which
    // here it does; five seconds of throat-clearing cannot be skimmed past.
    // And the model preambles *more* as the question gets harder, which is
    // exactly when leading with the answer matters most.
    final AgentPromptContext zh = composeAgentPrompt(
      profile: AgentProfile(),
      prompt: '幫我比較跑步和游泳對膝蓋的影響。',
    );
    expect(zh.systemInstruction, contains('第一句'));
    expect(
      zh.systemInstruction,
      contains('這個問題很複雜'),
      reason: 'naming the preamble it must not open with is what moved it',
    );

    final AgentPromptContext en = composeAgentPrompt(
      profile: AgentProfile(),
      prompt: 'Compare running and swimming for my knees.',
    );
    expect(en.systemInstruction, contains('first sentence'));
  });

  test('the length names what makes an answer long, not just a ceiling', () {
    // A ceiling is read as a target. Measured against the real model, 「三句話
    // 以內」 produced four answers of exactly three sentences to four
    // questions of wildly different weight, the third sentence of each one
    // padding — and in a running conversation it was worse, because the model
    // copies the shape of its own previous answers: the hardest question
    // came back at 48 characters in conversation against 89 asked alone.
    //
    // Naming the trigger instead — steps, comparisons, reasons — gives it a
    // rule it can apply per question rather than a habit it applies to all of
    // them. Same five questions, same seeds: 15 characters for 「早安」 and 201
    // for a comparison, against 16 and 48. See
    // `docs/decisions/answer-length-should-follow-the-question.md`.
    final AgentPromptContext concise = composeAgentPrompt(
      profile: AgentProfile(),
      prompt: '幫我想一個週末可以做的活動。',
    );
    expect(concise.systemInstruction, contains('一到三句'));
    expect(
      concise.systemInstruction,
      contains('比較'),
      reason: 'the trigger has to be nameable in the question itself',
    );
    expect(
      concise.systemInstruction,
      contains('不要為了湊長度補話'),
      reason: 'without this the raised ceiling becomes the new target',
    );
  });

  test('the spoken length is a sentence budget, not an adjective', () {
    // "Concise" produced answers averaging 172 characters — 27 seconds of
    // Mandarin speech for a conversational question. The same profile with a
    // sentence budget produced 64. The word was not the instruction; the
    // number is.
    final AgentPromptContext concise = composeAgentPrompt(
      profile: AgentProfile(),
      prompt: '幫我想一個週末可以做的活動。',
    );
    expect(concise.systemInstruction, contains('一到三句'));
    expect(concise.systemInstruction, contains('這是用說的'));

    final AgentPromptContext detailed = composeAgentPrompt(
      profile: AgentProfile(
        personality: const AgentPersonality(
          responseLength: AgentResponseLength.detailed,
        ),
      ),
      prompt: '幫我想一個週末可以做的活動。',
    );
    expect(detailed.systemInstruction, isNot(contains('一到三句')));

    // The budget belongs to the section about speaking, because that is what
    // it is a constraint on.
    final int spoken = concise.systemInstruction.indexOf('[語音回答方式]');
    final int preferences = concise.systemInstruction.indexOf('[使用者偏好]');
    final int budget = concise.systemInstruction.indexOf('一到三句');
    expect(budget, greaterThan(spoken));
    expect(budget, lessThan(preferences));
  });

  test('the English spoken length carries the same budget', () {
    final AgentPromptContext result = composeAgentPrompt(
      profile: AgentProfile(),
      prompt: 'Suggest something to do this weekend.',
    );
    expect(result.systemInstruction, contains('three sentences'));
    expect(result.systemInstruction, contains('being spoken aloud'));
  });

  test(
    'a profile that does not want short spoken sentences gets no budget',
    () {
      final AgentPromptContext result = composeAgentPrompt(
        profile: AgentProfile(
          voiceBehavior: const VoiceResponseBehavior(
            preferNaturalShortSentences: false,
          ),
        ),
        prompt: '幫我想一個週末可以做的活動。',
      );
      expect(result.systemInstruction, isNot(contains('一到三句')));
    },
  );

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

  // Asked the time with nothing in the prompt to answer from, gemma-4-E4B
  // does not say it cannot know — it invents one. Probed against the real
  // model with a clock tool registered and the instruction this app really
  // sends, it called the tool 0 times out of 5 and made the answer up every
  // time. A wrong answer that sounds certain is worse than no answer, so
  // the clock is told rather than fetched.
  // See `docs/decisions/tool-calling-readiness.md`.
  test('the current time reaches the model without being asked for', () {
    final AgentProfile profile = AgentProfile(
      identity: const AgentIdentity(userName: 'Yii'),
    );

    final AgentPromptContext result = composeAgentPrompt(
      profile: profile,
      prompt: '現在幾點？',
      now: DateTime(2026, 8, 7, 2, 53),
    );

    // The turn half, not the stable half. The system instruction is
    // prefilled once per conversation and a clock in it would rebuild the
    // whole prompt every turn — the 1648ms that
    // `docs/decisions/voice-turn-latency.md` measured and removed.
    expect(result.systemInstruction, isNot(contains('2026')));
    expect(result.turnInstruction, contains('[現在]'));
    expect(result.turnInstruction, contains('2026 年 8 月 7 日'));
    expect(result.turnInstruction, contains('星期五'));
    expect(result.turnInstruction, contains('02:53'));

    // Still last, so the question is the most recent thing the model read.
    expect(result.turnInstruction, endsWith('[問題]\n現在幾點？'));
  });

  // The one invariant the whole shape rests on. The clock is in the turn
  // half so the stable half can be prefilled once per conversation; a clock
  // that reached the stable half would expire between every question and
  // rebuild the prompt every turn, which
  // `docs/decisions/voice-turn-latency.md` measured at 1648ms against 362ms.
  // The existing guard only asserted the system half has no '2026' in it,
  // which passes for every year but one.
  test('two turns minutes apart are prefilled from the same text', () {
    final AgentProfile profile = AgentProfile(
      identity: const AgentIdentity(userName: 'Yii'),
    );

    final AgentPromptContext first = composeAgentPrompt(
      profile: profile,
      prompt: '現在幾點？',
      now: DateTime(2026, 8, 7, 2, 53),
    );
    final AgentPromptContext later = composeAgentPrompt(
      profile: profile,
      prompt: '現在幾點？',
      now: DateTime(2027, 1, 1, 23, 8),
    );

    expect(first.systemInstruction, later.systemInstruction);
    expect(first.turnInstruction, isNot(later.turnInstruction));
  });

  // A UTC clock rendered as if it were the wall clock is a confidently wrong
  // time, which is the failure the parameter exists to remove. The codebase
  // already has `_now().toUtc()` in it, so a caller could reach for one.
  test('a clock that is not the wall clock is refused', () {
    expect(
      () => composeAgentPrompt(
        profile: AgentProfile(identity: const AgentIdentity(userName: 'Yii')),
        prompt: '現在幾點？',
        now: DateTime.utc(2026, 8, 7, 2, 53),
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('the clock is written in the language of the question', () {
    final AgentPromptContext result = composeAgentPrompt(
      profile: AgentProfile(identity: const AgentIdentity(userName: 'Yii')),
      prompt: 'What time is it?',
      now: DateTime(2026, 8, 7, 14, 5),
    );

    expect(result.turnInstruction, contains('[Now]'));
    expect(result.turnInstruction, contains('Friday, 7 August 2026'));
    expect(result.turnInstruction, contains('14:05'));
  });

  // A caller that has no clock to offer must not be given a made-up one:
  // silence is honest, an invented timestamp is not.
  test('a turn composed without a clock says nothing about the time', () {
    final AgentPromptContext result = composeAgentPrompt(
      profile: AgentProfile(identity: const AgentIdentity(userName: 'Yii')),
      prompt: '現在幾點？',
    );

    expect(result.turnInstruction, isNot(contains('[現在]')));
    expect(result.turnInstruction, '[問題]\n現在幾點？');
  });

  // An English instruction with a Chinese sentence in it, in a composer
  // whose own comment says a small model answers in the language it was
  // instructed in. The built-in tone is a Chinese phrase and was being
  // rendered raw into both languages, so every English prompt this app sent
  // carried 「Tone: 親近但不裝熟.」 — including the one the tool-calling
  // measurement was taken against.
  test('an English instruction is written only in English', () {
    final AgentPromptContext result = composeAgentPrompt(
      profile: AgentProfile(identity: const AgentIdentity(userName: 'Yii')),
      prompt: 'What time is it?',
    );

    expect(
      result.systemInstruction,
      isNot(matches(RegExp(r'[\u4e00-\u9fff]'))),
    );
  });

  test('a tone the user wrote is sent as they wrote it', () {
    // Skipping the built-in default must not swallow a tone somebody chose.
    final AgentPromptContext result = composeAgentPrompt(
      profile: AgentProfile(
        personality: const AgentPersonality(tone: 'blunt and terse'),
      ),
      prompt: 'What time is it?',
    );

    expect(result.systemInstruction, contains('blunt and terse'));
  });

  test('the built-in tone is still said once, in the right language', () {
    // Dropped from the preferences block because the core-identity block
    // already says it — not because it stopped being true.
    final AgentPromptContext chinese = composeAgentPrompt(
      profile: AgentProfile(),
      prompt: '現在幾點？',
    );

    expect(chinese.systemInstruction, contains('親近但不裝熟'));
    expect(
      '親近但不裝熟'.allMatches(chinese.systemInstruction).length,
      1,
      reason: 'said twice is one instruction competing with itself',
    );
  });

  // 40 pages do not fit in a 4096-token window and never were going to. What
  // goes in is chosen against the question, bounded, and reported — so the
  // user can check the answer against the file they can read themselves.
  test('a question about a document brings the relevant part with it', () {
    final AgentPromptContext result = composeAgentPrompt(
      profile: AgentProfile(),
      prompt: '他們保固幾年',
      document:
          '第三條 租賃期間\n本租約為期一年。\n\n'
          '第九條 保固\n出租人對房屋結構提供五年保固。',
    );

    expect(result.turnInstruction, contains('[文件裡相關的段落]'));
    expect(result.turnInstruction, contains('五年保固'));
    expect(result.documentCharacters, greaterThan(0));
    // The stable half stays prefillable: a document is this question's, not
    // the conversation's.
    expect(result.systemInstruction, isNot(contains('保固')));
    // And the question is still the last thing read.
    expect(result.turnInstruction, endsWith('[問題]\n他們保固幾年'));
  });

  test('a question the document says nothing about carries none of it', () {
    // The first paragraph is not an answer, and an answer built on an
    // irrelevant passage is worse than one that admits it does not know —
    // in an app whose core instruction is 不捏造資訊.
    final AgentPromptContext result = composeAgentPrompt(
      profile: AgentProfile(),
      prompt: '今天台北的天氣如何',
      document: '第九條 保固\n出租人對房屋結構提供五年保固。',
    );

    expect(result.turnInstruction, isNot(contains('[文件裡相關的段落]')));
    expect(result.documentCharacters, 0);
  });
}
