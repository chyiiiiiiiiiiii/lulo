import 'package:agent_core/agent_core.dart';

/// A usable profile plus non-fatal details from defensive decoding.
final class AgentProfileDecodeResult {
  /// Creates one decoding outcome.
  AgentProfileDecodeResult({
    required this.profile,
    List<String> skippedMemoryIds = const <String>[],
    this.error,
  }) : skippedMemoryIds = List<String>.unmodifiable(skippedMemoryIds);

  /// Profile safe to use immediately.
  final AgentProfile profile;

  /// Invalid memory IDs omitted from [profile].
  final List<String> skippedMemoryIds;

  /// Root or schema failure that made the built-in profile necessary.
  final String? error;
}

/// Defensively decodes the developer-authored schema without throwing.
AgentProfileDecodeResult decodeAgentProfile(Object? json) {
  if (json is! Map<String, Object?>) {
    return AgentProfileDecodeResult(
      profile: AgentProfile.builtIn(),
      error: 'The agent profile root must be a JSON object.',
    );
  }
  final Object? schema = json['schemaVersion'];
  if (schema != 1) {
    return AgentProfileDecodeResult(
      profile: AgentProfile.builtIn(),
      error: 'Unsupported schemaVersion: $schema.',
    );
  }
  final AgentProfile defaults = AgentProfile.builtIn();
  final Map<String, Object?> identity = _map(json['identity']);
  final Map<String, Object?> personality = _map(json['personality']);
  final Map<String, Object?> voice = _map(json['voiceBehavior']);
  final List<String> skipped = <String>[];
  final List<AgentMemory> memories = <AgentMemory>[];
  final Object? rawMemories = json['memories'];
  if (rawMemories is List<Object?>) {
    for (final Object? raw in rawMemories) {
      final Map<String, Object?> item = _map(raw);
      final String id = _string(item['id'], '');
      try {
        memories.add(
          AgentMemory(
            id: id,
            kind: _memoryKind(item['kind']),
            content: _string(item['content'], ''),
            triggers: _strings(item['triggers']),
            enabled: _boolean(item['enabled'], true),
          ),
        );
      } on ArgumentError {
        skipped.add(id.isEmpty ? '<unknown>' : id);
      }
    }
  }
  return AgentProfileDecodeResult(
    profile: AgentProfile(
      identity: AgentIdentity(
        agentName: _string(identity['agentName'], defaults.identity.agentName),
        userName: _string(identity['userName'], defaults.identity.userName),
        locale: _string(identity['locale'], defaults.identity.locale),
      ),
      personality: AgentPersonality(
        tone: _string(personality['tone'], defaults.personality.tone),
        responseLength: _responseLength(personality['responseLength']),
        admitUncertainty: _boolean(
          personality['admitUncertainty'],
          defaults.personality.admitUncertainty,
        ),
        leadWithAnswer: _boolean(
          personality['leadWithAnswer'],
          defaults.personality.leadWithAnswer,
        ),
      ),
      voiceBehavior: VoiceResponseBehavior(
        avoidMarkdown: _boolean(
          voice['avoidMarkdown'],
          defaults.voiceBehavior.avoidMarkdown,
        ),
        avoidReadingUrls: _boolean(
          voice['avoidReadingUrls'],
          defaults.voiceBehavior.avoidReadingUrls,
        ),
        avoidLongLists: _boolean(
          voice['avoidLongLists'],
          defaults.voiceBehavior.avoidLongLists,
        ),
        preferNaturalShortSentences: _boolean(
          voice['preferNaturalShortSentences'],
          defaults.voiceBehavior.preferNaturalShortSentences,
        ),
      ),
      memories: memories,
      vocabulary: _strings(json['vocabulary']),
      additionalInstructions: _strings(json['additionalInstructions']),
    ),
    skippedMemoryIds: skipped,
  );
}

Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : const <String, Object?>{};

String _string(Object? value, String fallback) =>
    value is String ? value : fallback;

bool _boolean(Object? value, bool fallback) => value is bool ? value : fallback;

List<String> _strings(Object? value) => value is List<Object?>
    ? List<String>.unmodifiable(value.whereType<String>())
    : const <String>[];

AgentResponseLength _responseLength(Object? value) =>
    AgentResponseLength.values.asNameMap()[value] ??
    AgentResponseLength.concise;

AgentMemoryKind _memoryKind(Object? value) =>
    AgentMemoryKind.values.asNameMap()[value] ?? AgentMemoryKind.personal;
