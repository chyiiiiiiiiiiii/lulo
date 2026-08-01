/// How much detail Lulo should provide unless the question requires more.
enum AgentResponseLength { concise, balanced, detailed }

/// The stable names and language used to address each other.
final class AgentIdentity {
  const AgentIdentity({
    this.agentName = 'Lulo',
    this.userName = '',
    this.locale = 'zh-TW',
  });

  final String agentName;
  final String userName;
  final String locale;

  @override
  bool operator ==(Object other) =>
      other is AgentIdentity &&
      other.agentName == agentName &&
      other.userName == userName &&
      other.locale == locale;

  @override
  int get hashCode => Object.hash(agentName, userName, locale);
}

/// The interpersonal behavior of the agent, independently of its voice.
final class AgentPersonality {
  const AgentPersonality({
    this.tone = '親近但不裝熟',
    this.responseLength = AgentResponseLength.concise,
    this.admitUncertainty = true,
    this.leadWithAnswer = true,
  });

  final String tone;
  final AgentResponseLength responseLength;
  final bool admitUncertainty;
  final bool leadWithAnswer;

  @override
  bool operator ==(Object other) =>
      other is AgentPersonality &&
      other.tone == tone &&
      other.responseLength == responseLength &&
      other.admitUncertainty == admitUncertainty &&
      other.leadWithAnswer == leadWithAnswer;

  @override
  int get hashCode =>
      Object.hash(tone, responseLength, admitUncertainty, leadWithAnswer);
}

/// Rules that keep generated prose natural when it is read aloud.
final class VoiceResponseBehavior {
  const VoiceResponseBehavior({
    this.avoidMarkdown = true,
    this.avoidReadingUrls = true,
    this.avoidLongLists = true,
    this.preferNaturalShortSentences = true,
  });

  final bool avoidMarkdown;
  final bool avoidReadingUrls;
  final bool avoidLongLists;
  final bool preferNaturalShortSentences;

  @override
  bool operator ==(Object other) =>
      other is VoiceResponseBehavior &&
      other.avoidMarkdown == avoidMarkdown &&
      other.avoidReadingUrls == avoidReadingUrls &&
      other.avoidLongLists == avoidLongLists &&
      other.preferNaturalShortSentences == preferNaturalShortSentences;

  @override
  int get hashCode => Object.hash(
    avoidMarkdown,
    avoidReadingUrls,
    avoidLongLists,
    preferNaturalShortSentences,
  );
}

/// The narrow product categories a durable memory may belong to.
enum AgentMemoryKind { personal, preference, project, vocabulary }

/// One explicit personal fact, selected by explainable string triggers.
final class AgentMemory {
  AgentMemory({
    required String id,
    required this.kind,
    required String content,
    List<String> triggers = const <String>[],
    this.enabled = true,
  }) : id = _required(id, 'id'),
       content = _required(content, 'content'),
       triggers = List<String>.unmodifiable(triggers);

  final String id;
  final AgentMemoryKind kind;
  final String content;
  final List<String> triggers;
  final bool enabled;

  static String _required(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, 'Must not be empty.');
    }
    return value.trim();
  }

  @override
  bool operator ==(Object other) =>
      other is AgentMemory &&
      other.id == id &&
      other.kind == kind &&
      other.content == content &&
      _listEquals(other.triggers, triggers) &&
      other.enabled == enabled;

  @override
  int get hashCode =>
      Object.hash(id, kind, content, Object.hashAll(triggers), enabled);
}

/// The complete developer-authored context available to prompt composition.
final class AgentProfile {
  AgentProfile({
    this.schemaVersion = 1,
    this.identity = const AgentIdentity(),
    this.personality = const AgentPersonality(),
    this.voiceBehavior = const VoiceResponseBehavior(),
    List<AgentMemory> memories = const <AgentMemory>[],
    List<String> vocabulary = const <String>[],
    List<String> additionalInstructions = const <String>[],
  }) : memories = List<AgentMemory>.unmodifiable(memories),
       vocabulary = List<String>.unmodifiable(vocabulary),
       additionalInstructions = List<String>.unmodifiable(
         additionalInstructions,
       );

  factory AgentProfile.builtIn() => AgentProfile();

  final int schemaVersion;
  final AgentIdentity identity;
  final AgentPersonality personality;
  final VoiceResponseBehavior voiceBehavior;
  final List<AgentMemory> memories;
  final List<String> vocabulary;
  final List<String> additionalInstructions;

  @override
  bool operator ==(Object other) =>
      other is AgentProfile &&
      other.schemaVersion == schemaVersion &&
      other.identity == identity &&
      other.personality == personality &&
      other.voiceBehavior == voiceBehavior &&
      _listEquals(other.memories, memories) &&
      _listEquals(other.vocabulary, vocabulary) &&
      _listEquals(other.additionalInstructions, additionalInstructions);

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    identity,
    personality,
    voiceBehavior,
    Object.hashAll(memories),
    Object.hashAll(vocabulary),
    Object.hashAll(additionalInstructions),
  );
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
