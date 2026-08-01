import 'agent_memory_selector.dart';
import 'agent_profile.dart';

/// The model-facing instruction and non-sensitive composition diagnostics.
final class AgentPromptContext {
  /// Creates the result of composing one user turn.
  AgentPromptContext({
    required this.instruction,
    required List<String> selectedMemoryIds,
    required this.profileCharacterCount,
  }) : selectedMemoryIds = List<String>.unmodifiable(selectedMemoryIds);

  /// Complete model input, including the current question exactly once.
  final String instruction;

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
              if (profile.voiceBehavior.avoidMarkdown) '不要使用 Markdown。',
              if (profile.voiceBehavior.avoidReadingUrls) '不要朗讀完整 URL。',
              if (profile.voiceBehavior.avoidLongLists) '避免冗長條列。',
              if (profile.voiceBehavior.preferNaturalShortSentences)
                '使用適合自然朗讀的短句。',
            ]
          : <String>[
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

  profileText = _appendSectionWithin(
    profileText,
    title: chinese ? '開發者額外指示' : 'Additional instructions',
    lines: profile.additionalInstructions,
    limit: effectiveLimit,
  );

  return AgentPromptContext(
    instruction:
        '$profileText\n\n${chinese ? '[問題]' : '[Question]'}\n$question',
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

String _zhLength(AgentResponseLength length) => switch (length) {
  AgentResponseLength.concise => '簡潔',
  AgentResponseLength.balanced => '適中',
  AgentResponseLength.detailed => '詳細',
};
