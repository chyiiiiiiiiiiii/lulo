import 'agent_memory_selector.dart';
import 'agent_profile.dart';
import 'document_passages.dart';

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
    this.documentCharacters = 0,
  }) : selectedMemoryIds = List<String>.unmodifiable(selectedMemoryIds);

  /// Who the agent is and how it answers: identical for every turn of a
  /// conversation in one language, and never contains the question.
  final String systemInstruction;

  /// What this question brought with it: the memories it made relevant, the
  /// clock if the caller had one, and the question itself, exactly once.
  final String turnInstruction;

  /// Complete model input, including the current question exactly once.
  ///
  /// The two halves joined, for a runtime with nowhere to put a system
  /// instruction of its own.
  String get instruction => '$systemInstruction\n\n$turnInstruction';

  /// IDs of memories that survived relevance and prompt-size bounds.
  final List<String> selectedMemoryIds;

  /// How much of the document went in, so the app can say it used some.
  ///
  /// Zero when no document was offered or when the question turned out not
  /// to be about it. Reported because an answer drawn from a file the user
  /// can read for themselves has to be checkable against it.
  final int documentCharacters;

  /// Characters of profile text: the stable half plus whatever memories
  /// this question pulled in.
  ///
  /// Not the length of everything sent. The clock sits between the memories
  /// and the question and is deliberately outside this, because the budget
  /// it guards is the profile's — a timestamp is not profile content and
  /// must not be able to push a memory out.
  final int profileCharacterCount;
}

/// The way a question came in, which decides the shape of the answer.
///
/// A spoken answer is heard once, in order, at talking speed — the rules
/// written for it (short sentences, no markup, a tight budget) exist
/// because 172 characters is twenty-seven seconds of Mandarin. A typed
/// answer is read: the eye skims, rereads, and follows structure, and the
/// listener's rules make it feel curt instead of respectful. The channel
/// lives in the stable half, so switching between typing and talking
/// rebuilds the conversation once — the same trade an edited profile
/// already makes.
enum AnswerChannel {
  /// The answer will be spoken aloud.
  spoken,

  /// The answer will be read on screen.
  written,
}

/// Composes Lulo's stable behavior and relevant personal context for one turn.
///
/// [now] is what the clock said when the question was asked. It must be a
/// local time — a UTC one would be rendered as if it were the wall clock,
/// which is the exact failure this exists to remove — and it is omitted by
/// a caller that has none.
///
/// Told rather than fetched. Probed against the real gemma-4-E4B with a
/// clock tool registered, this app's own system instruction in front of it,
/// and five attempts per condition: it called the tool 0 times out of 5, in
/// either language, at either temperature, and still 0 with a further
/// paragraph ordering it to. It invents a confident wrong time instead, in
/// an app whose core instruction says 不捏造資訊. Told the time in the
/// prompt, the same conditions answer 5/5 in Chinese and 5/5 in English.
/// `docs/decisions/tool-calling-readiness.md` has both tables.
///
/// [document] is one file the user has asked about. The passages of it that
/// this question is about join the turn half — the whole file does not fit
/// and was never going to, so what goes in is chosen against the question
/// and bounded by [maxDocumentCharacters]. A question the document says
/// nothing about contributes nothing, rather than the first paragraph.
///
/// It joins the turn half rather than the stable one. The system
/// instruction is prefilled once per conversation, so a clock inside it
/// would expire between every question and rebuild the prompt each turn —
/// the cost `docs/decisions/voice-turn-latency.md` measured at 1648ms and
/// removed. The turn half is read again anyway, and a timestamp is a dozen
/// tokens of it.
AgentPromptContext composeAgentPrompt({
  required AgentProfile profile,
  required String prompt,
  DateTime? now,
  String? document,
  String? frontmostApp,
  AnswerChannel channel = AnswerChannel.spoken,
  int maxDocumentCharacters = 1400,
  int maxProfileCharacters = 1200,
}) {
  assert(
    now == null || !now.isUtc,
    'A UTC clock would be rendered as the wall clock and read as a wrong '
    'time — the failure this parameter exists to remove.',
  );
  final String question = prompt.trim();
  // The whole stable half is translated rather than carrying one line that
  // asks for a language, and that is deliberate. Putting the request in the
  // turn half would leave the system instruction stable across a switch and
  // save the 1580 ms rebuild that `docs/decisions/voice-turn-latency.md`
  // measures — it was tried, and a small model answers in the language it
  // was instructed in whatever the request says. See `the instruction is
  // written in the language of the question` in the app's
  // `pigeon_inference_service_test.dart`, which pins it. Do not move this to
  // `AgentIdentity.locale` either: that would answer a Chinese question in
  // English for anyone whose profile said so.
  final bool chinese = _cjk.hasMatch(question);
  final List<String> sections = <String>[
    _section(
      chinese ? '核心人格' : 'Core identity',
      chinese
          ? <String>[
              '你是 ${profile.identity.agentName}，在使用者電腦上運作的私人助手。',
              // The identity anchor. Reworking the opening line for tool
              // calling cost the name three times in five at temperature
              // 0.7 — 「我叫 Gemma 4」 — and one specific sentence about
              // the one question that leaks restored it to five in five on
              // both channels, where the old absolutist opening had bought
              // it as a side effect.
              '被問到名字或身分時，你就是 ${profile.identity.agentName}。',
              '用臺灣繁體中文回答，親近但不裝熟。',
              // Two measurements collided here and this line is the
              // reconciliation. 「第一句就要是答案本身」 moved preamble-free
              // answers from one in five to four in five — and was then
              // measured killing tool calling outright, 5/5 to 0/5: a model
              // told the first sentence must BE the answer cannot stop to
              // call a tool first. The active ingredient the length doc
              // records is naming the banned preambles, so the ban keeps
              // its examples and the first-sentence absolutism goes.
              '先回答核心；不要用「這個問題很複雜」、「兩者不一樣」、「明白了」這類開場。',
              '不確定時坦白說明，不捏造資訊。',
            ]
          : <String>[
              'You are ${profile.identity.agentName}, a private assistant running on the user’s computer.',
              'When asked your name or what you are, you are '
                  '${profile.identity.agentName}.',
              'Answer in natural spoken English. Be warm without pretending familiarity.',
              // The English wording follows the Chinese, which is what was
              // measured; this side has not been.
              'Lead with the core of the answer; never open with how '
                  'complex the question is, that the two things differ, '
                  'or an acknowledgement like "Understood".',
              'State uncertainty honestly and never invent facts.',
            ],
    ),
    _section(
      channel == AnswerChannel.spoken
          ? (chinese ? '語音回答方式' : 'Spoken response')
          : (chinese ? '文字回答方式' : 'Written response'),
      channel == AnswerChannel.spoken
          ? (chinese
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
                    if (profile.voiceBehavior.avoidMarkdown)
                      'Do not use Markdown.',
                    if (profile.voiceBehavior.avoidReadingUrls)
                      'Do not read full URLs aloud.',
                    if (profile.voiceBehavior.avoidLongLists)
                      'Avoid long lists.',
                    if (profile.voiceBehavior.preferNaturalShortSentences)
                      'Use short sentences that sound natural when spoken.',
                  ])
          : (chinese
                ? <String>[
                    '這是打字的對話，回答是用眼睛讀的。',
                    _zhWrittenLength(profile.personality.responseLength),
                    '需要列點時用「-」開頭的短行；不要用其他 Markdown 語法。',
                  ]
                : <String>[
                    'This is a typed conversation; the answer is read on '
                        'screen.',
                    _writtenLength(profile.personality.responseLength),
                    'Use short lines starting with "-" when a list helps; '
                        'no other Markdown.',
                  ]),
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
    // Only when the user has said something of their own. The core-identity
    // block above already states the built-in tone, in the language of the
    // question; repeating it here said it twice, and said it in Chinese
    // inside an English instruction — 「Tone: 親近但不裝熟.」 — in a composer
    // whose own comment says a small model answers in the language it was
    // instructed in. A tone the user typed is theirs and goes through as
    // written, in whatever language they wrote it.
    if (profile.personality.tone.trim().isNotEmpty &&
        profile.personality.tone.trim() != const AgentPersonality().tone.trim())
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
  final String clockSection = now == null
      ? ''
      : '${chinese ? '[現在]' : '[Now]'}\n${_clock(now, chinese: chinese)}';
  // Which app is front changes between questions the way the clock does,
  // so it lives in the same half for the same measured reason. Told, not
  // fetched, like the clock: a fact this cheap and this current is
  // context, not a tool. Blank and absent are the same answer.
  final String desktopApp = frontmostApp?.trim() ?? '';
  final String desktopSection = desktopApp.isEmpty
      ? ''
      : chinese
      ? '[桌面]\n使用者正在使用 $desktopApp。'
      : '[Desktop]\nThe user is currently in $desktopApp.';
  final DocumentPassages passages = document == null
      ? DocumentPassages(const <String>[])
      : passagesFor(
          question: question,
          document: document,
          maxCharacters: maxDocumentCharacters,
        );
  final String documentSection = passages.passages.isEmpty
      ? ''
      : '${chinese ? '[文件裡相關的段落]' : '[From the document]'}\n'
            '${passages.passages.join('\n\n')}';

  // The question stays last, so it is the most recent thing the model read.
  final String turnInstruction = <String>[
    if (memories.isNotEmpty) memories,
    if (clockSection.isNotEmpty) clockSection,
    if (desktopSection.isNotEmpty) desktopSection,
    if (documentSection.isNotEmpty) documentSection,
    questionSection,
  ].join('\n\n');

  return AgentPromptContext(
    systemInstruction: systemInstruction,
    turnInstruction: turnInstruction,
    documentCharacters: passages.usedCharacters,
    selectedMemoryIds: selectedIds,
    profileCharacterCount: profileText.length,
  );
}

/// [now] as a sentence, in the language the question was asked in.
///
/// The weekday is spelled out because 「7 號」 alone does not tell the model
/// whether it is a working day, which is most of what a date is asked for.
/// Written by hand rather than through `intl`: `agent_core` is pure Dart
/// with no package dependencies, and this is two lookup tables.
String _clock(DateTime now, {required bool chinese}) {
  final String hour = now.hour.toString().padLeft(2, '0');
  final String minute = now.minute.toString().padLeft(2, '0');
  if (chinese) {
    return '現在是 ${now.year} 年 ${now.month} 月 ${now.day} 日'
        '（${_zhWeekdays[now.weekday - 1]}）$hour:$minute。';
  }
  return 'It is ${_enWeekdays[now.weekday - 1]}, ${now.day} '
      '${_enMonths[now.month - 1]} ${now.year}, $hour:$minute.';
}

const List<String> _zhWeekdays = <String>[
  '星期一',
  '星期二',
  '星期三',
  '星期四',
  '星期五',
  '星期六',
  '星期日',
];

const List<String> _enWeekdays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _enMonths = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

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

/// How long an answer may run, as a typical length and what raises it.
///
/// The adjective on its own was not an instruction. Asked five
/// conversational questions with `concise` spelled out only as 簡潔,
/// gemma-4-E4B answered in 172 characters on average — twenty-seven seconds
/// of Mandarin speech, where nobody in a conversation talks for twenty-seven
/// seconds. The same profile with a sentence budget answered in 64.
///
/// But a ceiling is read as a target. 「三句話以內」 produced four answers of
/// exactly three sentences to four questions of wildly different weight,
/// the third sentence of each one padding — and in a running conversation it
/// was worse, because the model copies the shape of its own previous
/// answers: the heaviest question came back at 48 characters in conversation
/// against 89 asked alone. A mean length cannot see that; the spread can.
///
/// So this names a typical length **and** what raises it. The triggers are
/// words that appear in the question itself — steps, a comparison, a reason
/// — which gives the model a rule it can apply per question rather than a
/// habit it applies to all of them. Measured over the same five questions,
/// in one conversation: 15 characters for 「早安」 and 201 for a comparison,
/// against 16 and 48 for the ceiling.
///
/// The last clause is not decoration. Without 「不要為了湊長度補話」 the
/// raised ceiling becomes the new target and every answer grows to eight
/// sentences instead of three — the same defect with a bigger number.
///
/// An escape clause was measured too and is worse: 「三句話以內，除非使用者要
/// 細節」 compressed the spread further *and* loosened the identity block
/// three sections above it, answering 「我叫 Gemma 4。我是由 Google DeepMind
/// 開發的。」 to its own name. See
/// `docs/decisions/answer-length-should-follow-the-question.md`.
String _zhSpokenLength(AgentResponseLength length) => switch (length) {
  AgentResponseLength.concise =>
    '多數問題一到三句就夠；需要步驟、比較或說明原因時可以到七八句。'
        '講完就停，不要為了湊長度補話。',
  AgentResponseLength.balanced =>
    '多數問題一到五句就夠；需要步驟、比較或說明原因時可以更長。'
        '講完就停，不要為了湊長度補話。',
  AgentResponseLength.detailed => '可以講得完整一些，但仍然是講話，不是寫文章。',
};

/// [_zhSpokenLength] for a question asked in English.
String _spokenLength(AgentResponseLength length) => switch (length) {
  AgentResponseLength.concise =>
    'One to three sentences answer most questions; go to seven or eight '
        'when the question needs steps, a comparison, or a reason. Stop when '
        'you are done, and never pad to fill the room.',
  AgentResponseLength.balanced =>
    'One to five sentences answer most questions; go longer when the '
        'question needs steps, a comparison, or a reason. Stop when you are '
        'done, and never pad to fill the room.',
  AgentResponseLength.detailed =>
    'You may answer more fully, but this is still talking, not writing.',
};

/// [_zhSpokenLength] for an answer that will be read, not heard.
///
/// The B-shape from `answer-length-should-follow-the-question.md` — named
/// triggers the model can evaluate per question — without the ear's
/// framing: a reader skims and rereads, so the ceilings loosen one notch
/// and structure is allowed instead of feared.
String _zhWrittenLength(AgentResponseLength length) => switch (length) {
  // The B lines verbatim, not a rewrite: the first written draft replaced
  // 「可以到七八句」 with the open-ended 「把它說完整」, and the probe
  // measured the C-variant failure both ways at once — 「我是 Gemma 4」
  // and the clock tool at 0/5. An open-ended clause loosens far more than
  // the sentence it is in; a numbered ceiling does not.
  AgentResponseLength.concise =>
    '多數問題一到三句就夠；需要步驟、比較或說明原因時可以到七八句。'
        '講完就停，不要為了湊長度補話。',
  AgentResponseLength.balanced =>
    '多數問題一到五句就夠；需要步驟、比較或說明原因時可以更長。'
        '講完就停，不要為了湊長度補話。',
  AgentResponseLength.detailed => '可以講得完整一些，分段說清楚。',
};

/// [_zhWrittenLength] for a question asked in English.
String _writtenLength(AgentResponseLength length) => switch (length) {
  AgentResponseLength.concise =>
    'One to three sentences answer most questions; go to seven or eight '
        'when the question needs steps, a comparison, or a reason. Stop '
        'when you are done, and never pad to fill the room.',
  AgentResponseLength.balanced =>
    'One to five sentences answer most questions; go longer when the '
        'question needs steps, a comparison, or a reason. Stop when you '
        'are done, and never pad to fill the room.',
  AgentResponseLength.detailed =>
    'You may answer more fully, in paragraphs, spelled out.',
};

String _zhLength(AgentResponseLength length) => switch (length) {
  AgentResponseLength.concise => '簡潔',
  AgentResponseLength.balanced => '適中',
  AgentResponseLength.detailed => '詳細',
};
