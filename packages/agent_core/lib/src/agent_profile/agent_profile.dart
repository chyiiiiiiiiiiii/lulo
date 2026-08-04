/// How much detail Lulo should provide unless the question requires more.
enum AgentResponseLength {
  /// Lead with a short answer and offer to expand.
  concise,

  /// Provide enough explanation for the ordinary case.
  balanced,

  /// Prefer a thorough answer when the user explicitly chooses it.
  detailed,
}

/// The stable names and language used to address each other.
final class AgentIdentity {
  /// Creates the stable names and locale used by prompt composition.
  const AgentIdentity({
    this.agentName = 'Lulo',
    this.userName = '',
    this.locale = 'zh-TW',
  });

  /// The assistant's chosen name.
  final String agentName;

  /// How the assistant may address the user, empty when unspecified.
  final String userName;

  /// BCP-47 locale for the user's preferred language and region.
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
  /// Creates the interpersonal behavior used for every answer.
  const AgentPersonality({
    this.tone = '親近但不裝熟',
    this.responseLength = AgentResponseLength.concise,
    this.admitUncertainty = true,
    this.leadWithAnswer = true,
  });

  /// Human-readable relationship style.
  final String tone;

  /// Default amount of detail.
  final AgentResponseLength responseLength;

  /// Whether uncertainty must be stated rather than hidden.
  final bool admitUncertainty;

  /// Whether the useful answer should precede background explanation.
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
  /// Creates the rules applied to prose that may be spoken aloud.
  const VoiceResponseBehavior({
    this.avoidMarkdown = true,
    this.avoidReadingUrls = true,
    this.avoidLongLists = true,
    this.preferNaturalShortSentences = true,
  });

  /// Whether generated prose should omit Markdown syntax.
  final bool avoidMarkdown;

  /// Whether full URLs should be described instead of read character by character.
  final bool avoidReadingUrls;

  /// Whether long enumerations should be replaced by a concise summary.
  final bool avoidLongLists;

  /// Whether short natural sentences are preferred for speech.
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

/// The words this app is about, which nothing downstream can invent.
///
/// Two places need them and neither can derive them: the recogniser biases
/// towards them so a product name is not transcribed as whatever ordinary
/// words it sounds like, and the transcript refiner refuses to edit them
/// away. Left to a profile file, they existed only on the machine of whoever
/// had written one — which is how a check for them passed on one developer's
/// disk and could never pass anywhere else.
///
/// Deliberately short. Contextual biasing trades general accuracy for the
/// terms listed, so this is the vocabulary of the product, not a dictionary;
/// anything about the user belongs in their own profile.
const List<String> builtInVocabulary = <String>[
  'Lulo',
  'Flutter',
  'Dart',
  'Gemma',
  'LiteRT',
  'Qwen',
  'MLX',
  'Swift',
  'Xcode',
  'Claude',
];

/// The narrow product categories a durable memory may belong to.
enum AgentMemoryKind {
  /// A stable fact about the user, such as their chosen name.
  personal,

  /// A stated interaction or output preference.
  preference,

  /// Context about a named project or ongoing body of work.
  project,

  /// A term whose spelling or interpretation should remain stable.
  vocabulary,
}

/// One explicit personal fact, selected by explainable string triggers.
final class AgentMemory {
  /// Creates a validated memory with explicitly owned triggers.
  AgentMemory({
    required String id,
    required this.kind,
    required String content,
    List<String> triggers = const <String>[],
    this.enabled = true,
  }) : id = _required(id, 'id'),
       content = _required(content, 'content'),
       triggers = List<String>.unmodifiable(triggers);

  /// Stable identifier used for diagnostics and future editing.
  final String id;

  /// Product category governing triggerless eligibility.
  final AgentMemoryKind kind;

  /// Concise fact inserted into a relevant prompt.
  final String content;

  /// Substrings that make this memory relevant to a user turn.
  final List<String> triggers;

  /// Whether this memory may currently be selected.
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
  /// Creates a versioned immutable developer profile.
  AgentProfile({
    this.schemaVersion = 1,
    this.identity = const AgentIdentity(),
    this.personality = const AgentPersonality(),
    this.voiceBehavior = const VoiceResponseBehavior(),
    List<AgentMemory> memories = const <AgentMemory>[],
    List<String> vocabulary = builtInVocabulary,
    List<String> additionalInstructions = const <String>[],
  }) : memories = List<AgentMemory>.unmodifiable(memories),
       vocabulary = List<String>.unmodifiable(vocabulary),
       additionalInstructions = List<String>.unmodifiable(
         additionalInstructions,
       );

  /// Creates Lulo's safe profile when no valid local file is available.
  factory AgentProfile.builtIn() => AgentProfile();

  /// Schema version of the decoded profile.
  final int schemaVersion;

  /// Stable names and locale.
  final AgentIdentity identity;

  /// Interpersonal answer behavior.
  final AgentPersonality personality;

  /// Constraints for prose that may be spoken aloud.
  final VoiceResponseBehavior voiceBehavior;

  /// Structured facts eligible for deterministic selection.
  final List<AgentMemory> memories;

  /// Terms available to later ASR and transcript-refinement slices.
  final List<String> vocabulary;

  /// Developer-authored instructions appended after bounded memories.
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
