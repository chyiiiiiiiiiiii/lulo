import 'agent_profile.dart';

/// Why a memory was refused, or null when it may be written.
///
/// A reason rather than a bool so a caller can say what happened without
/// re-deriving it, and so a refusal is legible in a log that must never
/// contain the content itself.
enum AgentMemoryRefusal {
  /// It reads as an instruction to the agent rather than a fact about the
  /// user.
  instruction,

  /// It looks like a secret nobody should have written down.
  secret,
}

/// Whether [content] may be written to the profile by [source].
///
/// This is Layer 2 of the defence OWASP's agent-memory guidance describes —
/// sanitisation before persistence — and it exists because of what memory
/// *is* here: every entry is eligible to be pasted into the instruction of
/// every future turn, forever, by `composeAgentPrompt`. A sentence that
/// reads as a directive does not sit in the profile as a fact about the
/// user. It sits there as a standing order.
///
/// That failure has a name and a number. Memory poisoning is ASI06 in
/// OWASP's 2026 top ten for agentic applications, rated high-persistence
/// and very-hard-to-detect, and the reason it is rated that way is that
/// injection and execution are separated by weeks: nothing looks wrong at
/// the moment the memory is written, and by the time behaviour changes the
/// conversation that caused it is gone.
///
/// **What this app is and is not exposed to.** The extraction pass reads
/// exactly one thing — the text of the user's own turn. Not the model's
/// answer, not an open document, not the frontmost app, not a tool result.
/// So the classic path, where a poisoned web page or PDF is summarised into
/// memory, does not exist here, and that is a property of the wiring rather
/// than of this function. Two things remain, and they are why this is not
/// skipped:
///
/// - **A microphone hears the room.** A transcript is not the user's
///   intent; it is whatever was loud enough, including a video, a podcast,
///   or somebody else. Voice is the one input where "the user said it"
///   stops being a trust boundary.
/// - **A user can be talked into saying something.** The Gemini
///   memory-persistence attack worked by planting a conditional and waiting
///   for an ordinary 「好」 to trigger it.
///
/// **Deliberately narrow, and only for [AgentMemorySource.agent].** What
/// the user types into the settings sheet is theirs and goes in as written
/// — 「以後都用英文回答我」 typed on purpose is a legitimate instruction, and
/// a filter that refused it would be a filter fighting the user. Only the
/// unattended path is screened.
///
/// **And it is a floor, not a filter.** MINJA-style attacks are built
/// precisely to carry no injection signature, and no pattern list catches
/// what is designed to look ordinary. The controls that actually carry the
/// weight here are the ones around it: the pass is off by default, its
/// input is one sentence the user said rather than anything fetched, every
/// entry records [AgentMemorySource] so a bad one can be found and
/// attributed, and every entry is a row on a settings sheet with a switch
/// and a forget button. This just declines the obvious.
AgentMemoryRefusal? screenAgentMemory(
  String content, {
  required AgentMemorySource source,
}) {
  if (source != AgentMemorySource.agent) {
    return null;
  }
  final String folded = content.toLowerCase();
  for (final RegExp pattern in _instructionShapes) {
    if (pattern.hasMatch(folded)) {
      return AgentMemoryRefusal.instruction;
    }
  }
  for (final RegExp pattern in _secretShapes) {
    if (pattern.hasMatch(folded)) {
      return AgentMemoryRefusal.secret;
    }
  }
  return null;
}

/// Sentences that would act rather than inform.
///
/// Aimed at the override, not at the second person. 「使用者希望你回答短一
/// 點」 is a preference, contains 你, and is exactly the kind of memory this
/// feature exists to keep — so a rule that refused every 你 would refuse
/// the feature. What is refused is the shape that tries to *replace* the
/// instruction it is pasted next to.
final List<RegExp> _instructionShapes = <RegExp>[
  // Overriding what came before, which is the classic form and still the
  // most common one.
  RegExp(
    r'(ignore|disregard|forget)\s+(all\s+|any\s+)?(previous|prior|earlier|above|the\s+system)',
  ),
  RegExp(r'(忽略|無視|不要理會|不用理)(掉)?(之前|先前|上面|以上|前面|所有)?(的)?(指示|指令|規則|提示|設定)'),
  // Talking about the instruction itself.
  RegExp(r'(system\s*(prompt|instruction)|your\s+instructions)'),
  RegExp(r'(系統(提示|指令|訊息)|你的指示|你的設定)'),
  // Standing orders addressed to the agent. Third-person preferences
  // survive this: it needs both a permanence marker and an imperative
  // aimed at 你 / "you".
  RegExp(
    r'(from now on|always|never)\b[^.]{0,40}\b(you|your)\b\s*(must|should|will|have to)',
  ),
  RegExp(r'(從現在起|從今以後|以後每次|一律)[^。]{0,20}你(要|必須|得|應該|一定)'),
  // Reaching outward, which a fact about a person never does.
  RegExp(r'(https?://|<script|javascript:)'),
];

/// Shapes that are somebody's secret however they came up in conversation.
///
/// `docs/features/agent-profile.md` names these categories and says not to
/// put them in the profile. Saying so in a document protects a profile
/// nobody writes automatically; once something writes it automatically, the
/// sentence has to be enforced somewhere, and the write path is the only
/// place that sees every write.
///
/// Deliberately about *credentials and identifiers* rather than about
/// topics. A rule broad enough to catch 「我最近在看醫生」 would refuse a
/// large share of what a person says about themselves, and the honest
/// answer to a health-category policy is that it needs the privacy slice
/// `agent-profile.md` describes, not a regular expression.
final List<RegExp> _secretShapes = <RegExp>[
  RegExp(
    r'(password|passcode|passphrase|api[\s_-]?key|secret[\s_-]?key|private[\s_-]?key|seed\s+phrase|recovery\s+phrase)',
  ),
  RegExp(r'(密碼|通行碼|金鑰|助記詞|私鑰|驗證碼)'),
  RegExp(r'(身分證|身份證|健保卡|護照號|social\s+security|credit\s+card)'),
  // Twelve or more digits in a row, however grouped: card numbers, account
  // numbers, identifiers. A year, a price and a phone number all sit under
  // it.
  RegExp(r'(\d[\s-]?){12,}'),
];
