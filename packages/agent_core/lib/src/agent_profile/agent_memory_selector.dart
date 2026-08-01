import 'agent_profile.dart';

/// The bounded memories selected for one user turn.
final class AgentMemorySelection {
  AgentMemorySelection(List<AgentMemory> memories)
    : memories = List<AgentMemory>.unmodifiable(memories),
      characterCount = memories.fold<int>(
        0,
        (int total, AgentMemory memory) => total + memory.content.length,
      );

  final List<AgentMemory> memories;
  final int characterCount;

  List<String> get memoryIds => List<String>.unmodifiable(
    memories.map((AgentMemory memory) => memory.id),
  );
}

/// Selects explainable personal context without embeddings or tokenization.
AgentMemorySelection selectAgentMemories({
  required AgentProfile profile,
  required String prompt,
  int maxEntries = 6,
  int maxCharacters = 600,
}) {
  if (maxEntries <= 0 || maxCharacters <= 0) {
    return AgentMemorySelection(const <AgentMemory>[]);
  }
  final String normalizedPrompt = _normalize(prompt);
  final List<_Candidate> candidates = <_Candidate>[];
  for (int index = 0; index < profile.memories.length; index += 1) {
    final AgentMemory memory = profile.memories[index];
    if (!memory.enabled) {
      continue;
    }
    bool exact = false;
    int longestMatch = 0;
    for (final String rawTrigger in memory.triggers) {
      final String trigger = _normalize(rawTrigger);
      if (trigger.isEmpty || !normalizedPrompt.contains(trigger)) {
        continue;
      }
      exact = exact || normalizedPrompt == trigger;
      if (trigger.length > longestMatch) {
        longestMatch = trigger.length;
      }
    }
    final bool triggerless = memory.triggers.isEmpty;
    final bool alwaysEligible =
        triggerless &&
        (memory.kind == AgentMemoryKind.personal ||
            memory.kind == AgentMemoryKind.preference);
    if (longestMatch == 0 && !alwaysEligible) {
      continue;
    }
    candidates.add(
      _Candidate(
        memory: memory,
        sourceIndex: index,
        matched: longestMatch > 0,
        exact: exact,
        triggerLength: longestMatch,
      ),
    );
  }
  candidates.sort(_compareCandidates);

  final List<AgentMemory> selected = <AgentMemory>[];
  final Set<String> contentSeen = <String>{};
  int characters = 0;
  for (final _Candidate candidate in candidates) {
    final AgentMemory memory = candidate.memory;
    if (!contentSeen.add(memory.content)) {
      continue;
    }
    if (selected.length >= maxEntries) {
      break;
    }
    if (characters + memory.content.length > maxCharacters) {
      continue;
    }
    selected.add(memory);
    characters += memory.content.length;
  }
  return AgentMemorySelection(selected);
}

String _normalize(String value) => value.trim().toLowerCase();

int _compareCandidates(_Candidate left, _Candidate right) {
  final int matched = _boolRank(right.matched) - _boolRank(left.matched);
  if (matched != 0) {
    return matched;
  }
  final int exact = _boolRank(right.exact) - _boolRank(left.exact);
  if (exact != 0) {
    return exact;
  }
  final int triggerLength = right.triggerLength.compareTo(left.triggerLength);
  if (triggerLength != 0) {
    return triggerLength;
  }
  return left.sourceIndex.compareTo(right.sourceIndex);
}

int _boolRank(bool value) => value ? 1 : 0;

final class _Candidate {
  const _Candidate({
    required this.memory,
    required this.sourceIndex,
    required this.matched,
    required this.exact,
    required this.triggerLength,
  });

  final AgentMemory memory;
  final int sourceIndex;
  final bool matched;
  final bool exact;
  final int triggerLength;
}
