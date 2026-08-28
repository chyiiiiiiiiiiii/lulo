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

/// Writes [profile] back out in the schema [decodeAgentProfile] reads.
///
/// Every field is written, including the ones no screen shows. The decoder
/// reads a missing list as empty rather than as its default, so anything
/// omitted here is silently dropped the first time the user changes
/// something else. `vocabulary` is the one exception — absent keeps the
/// built-in terms, `[]` is believed — and it is an exception precisely
/// because omitting it once stripped all ten of them.
Map<String, Object?> encodeAgentProfile(AgentProfile profile) {
  return <String, Object?>{
    'schemaVersion': profile.schemaVersion,
    'identity': <String, Object?>{
      'agentName': profile.identity.agentName,
      'userName': profile.identity.userName,
      'locale': profile.identity.locale,
    },
    'personality': <String, Object?>{
      'tone': profile.personality.tone,
      'responseLength': profile.personality.responseLength.name,
      'admitUncertainty': profile.personality.admitUncertainty,
      'leadWithAnswer': profile.personality.leadWithAnswer,
    },
    'voiceBehavior': <String, Object?>{
      'avoidMarkdown': profile.voiceBehavior.avoidMarkdown,
      'avoidReadingUrls': profile.voiceBehavior.avoidReadingUrls,
      'avoidLongLists': profile.voiceBehavior.avoidLongLists,
      'preferNaturalShortSentences':
          profile.voiceBehavior.preferNaturalShortSentences,
    },
    'turnTaking': <String, Object?>{
      'acknowledgements': <String>[...profile.turnTaking.acknowledgements],
      'corrections': <String>[...profile.turnTaking.corrections],
      'unfinished': <String>[...profile.turnTaking.unfinished],
    },
    'memories': <Object?>[
      for (final AgentMemory memory in profile.memories)
        <String, Object?>{
          'id': memory.id,
          'kind': memory.kind.name,
          'content': memory.content,
          'triggers': <String>[...memory.triggers],
          'enabled': memory.enabled,
          'source': memory.source.name,
          if (memory.createdAt != null)
            'createdAt': memory.createdAt!.toIso8601String(),
        },
    ],
    'vocabulary': <String>[...profile.vocabulary],
    'misheard': <Map<String, Object?>>[
      for (final MisheardWord word in profile.misheard)
        <String, Object?>{'heard': word.heard, 'meant': word.meant},
    ],
    'respellings': <Map<String, Object?>>[
      for (final SpokenRespelling rule in profile.respellings)
        <String, Object?>{'word': rule.word, 'saidAs': rule.saidAs},
    ],
    'additionalInstructions': <String>[...profile.additionalInstructions],
  };
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
  final Map<String, Object?> turns = _map(json['turnTaking']);
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
            // An entry with no `source` predates provenance, and what those
            // entries actually are is hand-written — which is exactly what
            // `developer` means, so the default is the truth rather than a
            // placeholder.
            source:
                AgentMemorySource.values.asNameMap()[item['source']] ??
                AgentMemorySource.developer,
            createdAt: _time(item['createdAt']),
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
      turnTaking: TurnTakingWords(
        acknowledgements: _strings(turns['acknowledgements']),
        corrections: _strings(turns['corrections']),
        unfinished: _strings(turns['unfinished']),
      ),
      memories: memories,
      // Absent and empty are different answers. A file that never mentions
      // the vocabulary has said nothing about it and keeps the built-in
      // terms, which two places downstream cannot invent; a file that writes
      // `[]` has said it wants no biasing and is believed. Reading both as
      // empty stripped all ten terms from every hand-written profile, which
      // is the exact failure builtInVocabulary exists to prevent.
      vocabulary: json.containsKey('vocabulary')
          ? _strings(json['vocabulary'])
          : defaults.vocabulary,
      misheard: _misheard(json['misheard']),
      respellings: _respellings(json['respellings']),
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

/// A timestamp, or null for anything that is not one.
///
/// Null rather than a fallback of now: this column exists so a memory can be
/// attributed, and a decoder that invented a creation time would fill it
/// with a fact nobody checked.
DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

AgentMemoryKind _memoryKind(Object? value) =>
    AgentMemoryKind.values.asNameMap()[value] ?? AgentMemoryKind.personal;

/// Corrections the user has taught the recogniser, ignoring malformed rows.
///
/// A row missing either half is dropped rather than read as an empty
/// string: an empty `heard` would match between every pair of characters in
/// every transcript, so one bad row in a hand-edited file would rewrite
/// everything the user says.
/// The respelling table, dropping any row that cannot do anything.
///
/// Same rule as [_misheard] and for the same reason: a row missing either
/// half is dropped rather than read as an empty string, or one bad row in a
/// hand-edited file rewrites every sentence on its way to the voice.
List<SpokenRespelling> _respellings(Object? value) {
  if (value is! List<Object?>) {
    return const <SpokenRespelling>[];
  }
  final List<SpokenRespelling> rules = <SpokenRespelling>[];
  for (final Object? entry in value) {
    if (entry is! Map<Object?, Object?>) {
      continue;
    }
    final Object? word = entry['word'];
    final Object? saidAs = entry['saidAs'];
    if (word is! String || saidAs is! String) {
      continue;
    }
    final SpokenRespelling rule = SpokenRespelling(word: word, saidAs: saidAs);
    if (rule.isUsable) {
      rules.add(rule);
    }
  }
  return rules;
}

List<MisheardWord> _misheard(Object? value) {
  if (value is! List<Object?>) {
    return const <MisheardWord>[];
  }
  final List<MisheardWord> words = <MisheardWord>[];
  for (final Object? entry in value) {
    if (entry is! Map<Object?, Object?>) {
      continue;
    }
    final Object? heard = entry['heard'];
    final Object? meant = entry['meant'];
    if (heard is! String || meant is! String) {
      continue;
    }
    final MisheardWord word = MisheardWord(heard: heard, meant: meant);
    if (word.isUsable) {
      words.add(word);
    }
  }
  return words;
}
