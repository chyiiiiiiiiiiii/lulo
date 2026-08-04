import 'agent_memory_selector.dart';
import 'agent_profile.dart';

/// The model-facing instruction and non-sensitive composition diagnostics.
///
/// The instruction arrives in two parts because they cost different amounts
/// to say twice. [systemInstruction] is the same text for every turn of a
/// conversation, so a runtime that can hold it in a prefilled KV cache pays
/// for it once; [turnInstruction] is what this particular question dragged
/// in with it and has to be read every time. Sending the whole thing as one
/// user message re-prefills the stable half on every turn — measured on
/// gemma-4-E4B at 1.7s to the first token against 0.3s when the profile is
/// prefilled once.
final class AgentPromptContext {
  /// Creates the result of composing one user turn.
  AgentPromptContext({
    required this.systemInstruction,
    required this.turnInstruction,
    required List<String> selectedMemoryIds,
    required this.profileCharacterCount,
  }) : selectedMemoryIds = List<String>.unmodifiable(selectedMemoryIds);

  /// Who the agent is and how it answers: identical for every turn of a
  /// conversation in one language, and never contains the question.
  final String systemInstruction;

  /// What this question brought with it: the memories it made relevant, and
  /// the question itself, exactly once.
  final String turnInstruction;

  /// Complete model input, including the current question exactly once.
  ///
  /// The two halves joined, for a runtime with nowhere to put a system
  /// instruction of its own.
  String get instruction => '$systemInstruction\n\n$turnInstruction';

  /// IDs of memories that survived relevance and prompt-size bounds.
  final List<String> selectedMemoryIds;

  /// Characters before the final question section.
  final int profileCharacterCount;
}

/// Composes Lulo's stable behavior and relevant personal context for one turn.
AgentPromptContext composeAgentPrompt({
  required AgentProfile profile,
  required String prompt,
  int maxProfileCharacters = 1200,
}) {
  final String question = prompt.trim();
  final bool chinese = _cjk.hasMatch(question);
  final List<String> sections = <String>[
    _section(
      chinese ? '核心人格' : 'Core identity',
      chinese
          ? <String>[
              '你是 ${profile.identity.agentName}，在使用者電腦上運作的私人助手。',
              '用臺灣繁體中文回答，親近但不裝熟。',
              '先回答核心；不確定時坦白說明，不捏造資訊。',
            ]
          : <String>[
              'You are ${profile.identity.agentName}, a private assistant running on the user’s computer.',
              'Answer in natural spoken English. Be warm without pretending familiarity.',
              'Lead with the answer; state uncertainty honestly and never invent facts.',
            ],
    ),
    _section(
      chinese ? '語音回答方式' : 'Spoken response',
      chinese
          ? <String>[
              if (profile
                  .voiceBehavior
                  .preferNaturalShortSentences) ...<String>[
                '這是用說的，不是用寫的。',
                _zhSpokenLength(profile.personality.responseLength),
              ],
              if (profile.voiceBehavior.avoidMarkdown) '不要使用 Markdown。',
              if (profile.voiceBehavior.avoidReadingUrls) '不要朗讀完整 URL。',
              if (profile.voiceBehavior.avoidLongLists) '避免冗長條列。',
              if (profile.voiceBehavior.preferNaturalShortSentences)
                '使用適合自然朗讀的短句。',
            ]
          : <String>[
              if (profile
                  .voiceBehavior
                  .preferNaturalShortSentences) ...<String>[
                'This is being spoken aloud, not written.',
                _spokenLength(profile.personality.responseLength),
              ],
              if (profile.voiceBehavior.avoidMarkdown) 'Do not use Markdown.',
              if (profile.voiceBehavior.avoidReadingUrls)
                'Do not read full URLs aloud.',
              if (profile.voiceBehavior.avoidLongLists) 'Avoid long lists.',
              if (profile.voiceBehavior.preferNaturalShortSentences)
                'Use short sentences that sound natural when spoken.',
            ],
    ),
  ];
  final String required = sections.join('\n\n');
  final int effectiveLimit = maxProfileCharacters < required.length
      ? required.length
      : maxProfileCharacters;
  String profileText = required;

  final List<String> preferences = <String>[
    if (profile.identity.userName.trim().isNotEmpty)
      chinese
          ? '稱呼使用者：${profile.identity.userName.trim()}。'
          : 'Address the user as ${profile.identity.userName.trim()}.',
    if (profile.personality.tone.trim().isNotEmpty)
      chinese
          ? '語氣：${profile.personality.tone.trim()}。'
          : 'Tone: ${profile.personality.tone.trim()}.',
    chinese
        ? '回答長度：${_zhLength(profile.personality.responseLength)}。'
        : 'Answer length: ${profile.personality.responseLength.name}.',
  ];
  profileText = _appendSectionWithin(
    profileText,
    title: chinese ? '使用者偏好' : 'User preferences',
    lines: preferences,
    limit: effectiveLimit,
  );

  // Developer instructions are as stable as the personality they qualify, so
  // they join it ahead of the memories rather than after them. That is a
  // change of order from when everything was one block: the stable half has
  // to end somewhere, and it has to end at the same place every turn.
  profileText = _appendSectionWithin(
    profileText,
    title: chinese ? '開發者額外指示' : 'Additional instructions',
    lines: profile.additionalInstructions,
    limit: effectiveLimit,
  );
  final String systemInstruction = profileText;

  // Memories are chosen against this question, so they belong to the turn —
  // but they still spend from the one profile budget, appended to the stable
  // text so the limit sees everything that will be sent.
  final AgentMemorySelection selection = selectAgentMemories(
    profile: profile,
    prompt: question,
  );
  final List<String> selectedIds = <String>[];
  for (final AgentMemory memory in selection.memories) {
    final String candidate = _appendSectionWithin(
      profileText,
      title: chinese ? '與這次問題相關的記憶' : 'Relevant memory',
      lines: <String>[memory.content],
      limit: effectiveLimit,
    );
    if (candidate == profileText) {
      continue;
    }
    profileText = candidate;
    selectedIds.add(memory.id);
  }

  // Everything appended past the stable text, without the blank line that
  // joins the two halves back together.
  final String memories = profileText.length == systemInstruction.length
      ? ''
      : profileText.substring(systemInstruction.length + 2);
  final String questionSection =
      '${chinese ? '[問題]' : '[Question]'}\n$question';

  return AgentPromptContext(
    systemInstruction: systemInstruction,
    turnInstruction: memories.isEmpty
        ? questionSection
        : '$memories\n\n$questionSection',
    selectedMemoryIds: selectedIds,
    profileCharacterCount: profileText.length,
  );
}

final RegExp _cjk = RegExp(r'[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]');

String _section(String title, List<String> lines) =>
    '[$title]\n${lines.join('\n')}';

String _appendSectionWithin(
  String current, {
  required String title,
  required List<String> lines,
  required int limit,
}) {
  String result = current;
  for (final String rawLine in lines) {
    final String line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    final String header = '[$title]\n';
    final bool alreadyPresent = result.contains(header);
    final String addition = alreadyPresent ? '\n$line' : '\n\n$header$line';
    if (result.length + addition.length <= limit) {
      result += addition;
    }
  }
  return result;
}

/// How long a spoken answer may run, as a number of sentences.
///
/// The adjective on its own was not an instruction. Asked five
/// conversational questions with `concise` spelled out only as 簡潔,
/// gemma-4-E4B answered in 172 characters on average — twenty-seven seconds
/// of Mandarin speech, where nobody in a conversation talks for twenty-seven
/// seconds. The same profile with a sentence budget answered in 64, and the
/// answers were whole thoughts rather than truncated ones: one of them ended
/// by asking a question back.
///
/// Telling it to stop is not enough on its own — the second clause says
/// where the rest of the answer went, so stopping reads as leaving room
/// rather than as running out.
String _zhSpokenLength(AgentResponseLength length) => switch (length) {
  AgentResponseLength.concise => '回答控制在三句話以內；講完核心就停，細節等使用者追問再說。',
  AgentResponseLength.balanced => '回答控制在五句話以內；講完核心就停，細節等使用者追問再說。',
  AgentResponseLength.detailed => '可以講得完整一些，但仍然是講話，不是寫文章。',
};

/// [_zhSpokenLength] for a question asked in English.
String _spokenLength(AgentResponseLength length) => switch (length) {
  AgentResponseLength.concise =>
    'Answer in three sentences or fewer; stop after the core of it and '
        'leave the detail for the user to ask about.',
  AgentResponseLength.balanced =>
    'Answer in five sentences or fewer; stop after the core of it and '
        'leave the detail for the user to ask about.',
  AgentResponseLength.detailed =>
    'You may answer more fully, but this is still talking, not writing.',
};

String _zhLength(AgentResponseLength length) => switch (length) {
  AgentResponseLength.concise => '簡潔',
  AgentResponseLength.balanced => '適中',
  AgentResponseLength.detailed => '詳細',
};
