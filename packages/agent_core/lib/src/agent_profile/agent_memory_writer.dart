import 'agent_memory_screen.dart';
import 'agent_profile.dart';

/// What happened to a profile when one memory was written to it.
enum AgentMemoryWriteStatus {
  /// The list changed: a memory was added, or replaced others, or both.
  saved,

  /// The profile already said this and nothing needed doing.
  unchanged,

  /// Nothing was written, and [AgentMemoryWriteResult.error] says why.
  rejected,

  /// The screen refused it: it read as an instruction, or as a secret.
  ///
  /// Separate from [rejected] because the two want different handling. A
  /// rejection is a caller that asked for something impossible — too long,
  /// no room — and can try again differently. A refusal is a write that
  /// must not happen however it is phrased, and is worth counting.
  refused,
}

/// One write, and everything a caller needs to report it without guessing.
final class AgentMemoryWriteResult {
  /// Creates a result owning immutable copies of its lists.
  AgentMemoryWriteResult({
    required this.status,
    required List<AgentMemory> memories,
    this.id,
    this.kind,
    this.refusal,
    List<String> replacedIds = const <String>[],
    List<String> unknownReplaceIds = const <String>[],
    this.error,
  }) : memories = List<AgentMemory>.unmodifiable(memories),
       replacedIds = List<String>.unmodifiable(replacedIds),
       unknownReplaceIds = List<String>.unmodifiable(unknownReplaceIds);

  /// What the write did.
  final AgentMemoryWriteStatus status;

  /// The memory list as it should now be. Unchanged from the input when
  /// nothing was written, so a caller can save this unconditionally.
  final List<AgentMemory> memories;

  /// The memory this fact now lives in, or null when nothing was written.
  ///
  /// Not always a new id: writing a fact the profile already held returns
  /// the id it was already under, because the caller's next sentence is
  /// about *this fact*, not about whether it happened to be novel.
  final String? id;

  /// The kind the fact was actually stored under, or null when nothing was
  /// written.
  ///
  /// Reported because it is not always the kind that was asked for — see
  /// [recallableAgentMemoryKind] — and a caller that reported the requested
  /// kind would be telling the model it saved something it did not.
  final AgentMemoryKind? kind;

  /// Memories this one superseded, in the order they were named.
  final List<String> replacedIds;

  /// Ids named as superseded that no memory owns.
  ///
  /// Reported rather than refused. The new fact is worth more than the
  /// failed replacement, and the stale memory is still a row on the
  /// settings sheet — whereas rejecting the whole write would lose both.
  final List<String> unknownReplaceIds;

  /// Why nothing was written, for [AgentMemoryWriteStatus.rejected].
  final String? error;

  /// Which screen refused it, for [AgentMemoryWriteStatus.refused].
  ///
  /// The reason and never the content: a refused memory is the one string
  /// in this system most likely to be somebody's password.
  final AgentMemoryRefusal? refusal;
}

/// The longest fact worth keeping, in Unicode characters.
///
/// Sized against the prompt rather than against language: `composeAgentPrompt`
/// gives the whole profile 1200 characters and `selectAgentMemories` may pick
/// six, so a memory that ran to a paragraph would push out the personality
/// that makes the answer the agent's. Anything longer is a summary nobody has
/// written yet.
const int maxAgentMemoryCharacters = 160;

/// The most memories a profile may hold before writes stop adding.
///
/// A ceiling on a list nothing prunes. Past it a caller is told to have the
/// user forget one, rather than the app quietly dropping the oldest fact
/// about them — the one failure a memory feature must never have. Note that
/// a write which *replaces* is not blocked by this: correcting a fact has to
/// keep working on a full list, or the list becomes unfixable exactly when
/// it most needs fixing.
const int maxAgentMemories = 60;

/// Writes one fact into [profile]'s memories, superseding what it replaces.
///
/// The whole point of the [replaces] argument, and the reason this is not
/// an append: **memory that only appends is worse than no memory.** A
/// profile holding 「使用者住在台北」 from March and 「使用者搬到台南了」 from
/// August holds both, both are triggerless personal memories, and
/// `selectAgentMemories` puts both in the same prompt — two contradictory
/// facts, spending two shares of a 1200-character budget, in front of a
/// model asked to answer as though it knows the user. Not knowing is a
/// smaller failure than being fed the wrong thing confidently.
///
/// Which memory a new fact supersedes is the caller's to say, and
/// deliberately not inferred here. Deciding that 「搬到台南」 obsoletes
/// 「住在台北」 is semantics; the alternative on offer was a string-similarity
/// threshold, and one number cannot separate a rewrite from a contradiction
/// in two languages — Chinese character bigrams score those two pairs at
/// 0.71 and 0.31, English at 0.58 and lower, so any threshold that works on
/// one is wrong on the other. What decides it well, measured at 15/15 in
/// `RememberProbeTests`, is the model in a clean second pass, which can be
/// shown the whole list because the whole list is sixty short lines. See
/// `docs/decisions/the-model-will-not-interrupt-itself-to-remember.md`.
AgentMemoryWriteResult writeAgentMemory({
  required AgentProfile profile,
  required String content,
  AgentMemoryKind kind = AgentMemoryKind.personal,
  List<String> triggers = const <String>[],
  List<String> replaces = const <String>[],
  AgentMemorySource source = AgentMemorySource.developer,
  DateTime? now,
  int maxCharacters = maxAgentMemoryCharacters,
  int maxMemories = maxAgentMemories,
}) {
  final String fact = content.trim();
  if (fact.isEmpty) {
    return AgentMemoryWriteResult(
      status: AgentMemoryWriteStatus.rejected,
      memories: profile.memories,
      error: 'content is required: the one sentence to remember.',
    );
  }
  if (fact.length > maxCharacters) {
    return AgentMemoryWriteResult(
      status: AgentMemoryWriteStatus.rejected,
      memories: profile.memories,
      error:
          'content is ${fact.length} characters; keep it under '
          '$maxCharacters. Say the same fact more briefly.',
    );
  }

  // Before anything else looks at it, and before it can be compared against
  // what is already stored: a refused string should not reach the rest of
  // this function at all.
  final AgentMemoryRefusal? refusal = screenAgentMemory(fact, source: source);
  if (refusal != null) {
    return AgentMemoryWriteResult(
      status: AgentMemoryWriteStatus.refused,
      memories: profile.memories,
      refusal: refusal,
    );
  }

  final Set<String> owned = <String>{
    for (final AgentMemory memory in profile.memories) memory.id,
  };
  final List<String> replaced = <String>[];
  final List<String> unknown = <String>[];
  for (final String raw in replaces) {
    final String id = raw.trim();
    if (id.isEmpty || replaced.contains(id) || unknown.contains(id)) {
      continue;
    }
    (owned.contains(id) ? replaced : unknown).add(id);
  }

  // Against the profile as it stands, before anything is removed, so a
  // superseded id is never handed to the memory that superseded it. Reusing
  // it would make the profile file — which a person reads and edits — say
  // that `memory-3` is a fact it replaced.
  final String freshId = nextAgentMemoryId(profile);

  final String normalized = _normalize(fact);
  AgentMemory? already;
  for (final AgentMemory memory in profile.memories) {
    if (_normalize(memory.content) == normalized) {
      already = memory;
      break;
    }
  }

  final List<AgentMemory> kept = <AgentMemory>[
    for (final AgentMemory memory in profile.memories)
      if (!replaced.contains(memory.id)) memory,
  ];

  if (already != null && !replaced.contains(already.id)) {
    // The fact is already here. Any supersession asked for still happens —
    // that is the caller correcting the list — but nothing is appended, and
    // the id reported is the one the fact already lives under.
    return AgentMemoryWriteResult(
      status: replaced.isEmpty
          ? AgentMemoryWriteStatus.unchanged
          : AgentMemoryWriteStatus.saved,
      memories: kept,
      id: already.id,
      kind: already.kind,
      replacedIds: replaced,
      unknownReplaceIds: unknown,
    );
  }

  if (kept.length >= maxMemories) {
    return AgentMemoryWriteResult(
      status: AgentMemoryWriteStatus.rejected,
      memories: profile.memories,
      error:
          'The memory list is full at $maxMemories entries. Have the user '
          'forget one in Settings, or say which memory this replaces.',
      unknownReplaceIds: unknown,
    );
  }

  final List<String> ownTriggers = <String>[
    for (final String trigger in triggers)
      if (trigger.trim().isNotEmpty) trigger.trim(),
  ];
  final AgentMemoryKind stored = recallableAgentMemoryKind(
    kind,
    hasTriggers: ownTriggers.isNotEmpty,
  );
  return AgentMemoryWriteResult(
    status: AgentMemoryWriteStatus.saved,
    memories: <AgentMemory>[
      ...kept,
      AgentMemory(
        id: freshId,
        kind: stored,
        content: fact,
        triggers: ownTriggers,
        source: source,
        createdAt: now,
      ),
    ],
    id: freshId,
    kind: stored,
    replacedIds: replaced,
    unknownReplaceIds: unknown,
  );
}

/// The kind to store under, so that what is written can be read back.
///
/// A `project` or `vocabulary` memory with no triggers can never be
/// selected — `selectAgentMemories` lets a triggerless memory through only
/// when it is `personal` or `preference` — so storing one as asked would
/// write a fact the agent is structurally unable to recall, and report
/// success for it. The settings sheet resolves this by forcing `personal`
/// on anything typed without triggers; nothing that supplies triggers is
/// more reliable than that text field, so the same rule holds here, keeping
/// `preference` where it was chosen because that kind is eligible too.
AgentMemoryKind recallableAgentMemoryKind(
  AgentMemoryKind kind, {
  required bool hasTriggers,
}) {
  if (hasTriggers || kind == AgentMemoryKind.preference) {
    return kind;
  }
  return AgentMemoryKind.personal;
}

/// Case-folded, space-stripped, and without a trailing full stop.
///
/// Narrow on purpose. This catches the same sentence written twice, which
/// happens because a model rewrites its own wording between turns — five
/// extraction attempts on one sentence produced 「使用者搬到台南了。」,
/// 「使用者搬到了台南。」 and 「使用者搬到台南居住。」 in `RememberProbeTests`.
/// It does **not** try to catch those three as each other: that is a
/// judgement, it belongs to the caller, and a similarity threshold guessing
/// at it is how a rewrite and a contradiction end up on the same side of a
/// number.
String _normalize(String value) {
  final String folded = value.toLowerCase().replaceAll(_spaces, '');
  int end = folded.length;
  while (end > 0 && _sentenceEnd.contains(folded[end - 1])) {
    end -= 1;
  }
  return folded.substring(0, end);
}

final RegExp _spaces = RegExp(r'[\s　]+');
const String _sentenceEnd = '。．.！!？?、，,';
