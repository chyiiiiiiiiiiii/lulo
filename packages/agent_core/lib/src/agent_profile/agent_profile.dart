import '../voice/floor_control.dart';
import 'misheard_word.dart';

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
  /// Creates the stable names and the user's stated locale.
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
  ///
  /// **Nothing reads this.** The language of both the instructions and the
  /// answer is taken from the question itself, in `composeAgentPrompt`, and
  /// it has to be: an English preamble in front of a Chinese question turns
  /// the reply English however plainly the preamble asks otherwise, because
  /// on a model this size the instruction is the strongest signal in the
  /// prompt. That is pinned by `the instruction is written in the language of
  /// the question` in the app's `pigeon_inference_service_test.dart`.
  ///
  /// Kept because the voice path will need it. There the recogniser is
  /// monolingual — one locale chosen at `begin()` — so a transcript's script
  /// says what the recogniser was set to, not what the user spoke, and the
  /// question cannot be asked what language it is in.
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
/// The first of those two was a claim this sentence made and the code did
/// not keep: the profile reached the refiner and stopped there, while the
/// recogniser ran off a hardcoded list of its own. It is wired now, through
/// `VoiceHostApi.useSpokenVocabulary`. Do not read that as an accuracy win —
/// `SpokenVocabularyBook` records a measurement where a thirty-two term bias
/// changed the transcript by not one character, and nothing since has shown
/// otherwise. What is fixed is that the setting now reaches the thing it
/// names.
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

/// The user's own ways of saying "carry on", "stop", and "I have not
/// finished".
///
/// Every list here extends a built-in one rather than replacing it, and
/// every built-in one is a guess at how people talk. A user's habits are not
/// a guess — 「蛤」 or 「先停」 or a filler nobody else uses is exactly the thing
/// that makes the agent feel like it is listening or like it is not, and it
/// cannot be discovered from here.
///
/// The profile file is watched, so a word added while the app is running
/// takes effect on the next thing said.
final class TurnTakingWords {
  /// Creates the three lists, all empty by default.
  const TurnTakingWords({
    this.acknowledgements = const <String>[],
    this.corrections = const <String>[],
    this.unfinished = const <String>[],
  });

  /// Said while the agent talks and meaning "carry on" — never interrupts.
  ///
  /// A single character joins the repeatable set, so 「蛤」 also covers
  /// 「蛤蛤蛤」; anything longer is matched whole.
  final List<String> acknowledgements;

  /// Said while the agent talks and meaning "stop" — always interrupts,
  /// however short. Han entries match as a prefix, Latin ones by first word.
  final List<String> corrections;

  /// Ends a sentence that is not finished, so the endpointer waits longer.
  ///
  /// Read by `TurnCompletion` on the native side rather than by
  /// [FloorControl]: the endpointer runs on a 50ms tick in the audio path,
  /// where a hop across the channel costs more than the decision saves.
  final List<String> unfinished;

  @override
  bool operator ==(Object other) =>
      other is TurnTakingWords &&
      _listEquals(other.acknowledgements, acknowledgements) &&
      _listEquals(other.corrections, corrections) &&
      _listEquals(other.unfinished, unfinished);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(acknowledgements),
    Object.hashAll(corrections),
    Object.hashAll(unfinished),
  );
}

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
    this.turnTaking = const TurnTakingWords(),
    List<AgentMemory> memories = const <AgentMemory>[],
    List<String> vocabulary = builtInVocabulary,
    List<MisheardWord> misheard = const <MisheardWord>[],
    List<String> additionalInstructions = const <String>[],
  }) : floorControl = FloorControl(
         alsoAcknowledgements: turnTaking.acknowledgements,
         alsoCorrections: turnTaking.corrections,
       ),
       memories = List<AgentMemory>.unmodifiable(memories),
       vocabulary = List<String>.unmodifiable(vocabulary),
       misheard = List<MisheardWord>.unmodifiable(misheard),
       additionalInstructions = List<String>.unmodifiable(
         additionalInstructions,
       );

  /// Creates Lulo's safe profile when no valid local file is available.
  factory AgentProfile.builtIn() => AgentProfile();

  /// Returns a copy with the named parts replaced.
  ///
  /// Every edit made from settings rebuilds the whole profile, and the screen
  /// shows less of it than the file holds — so what is not named here has to
  /// come through untouched, or changing one thing would silently drop
  /// another. [floorControl] is rebuilt rather than carried over, because it
  /// is derived from [turnTaking] and carrying it would save a word and go on
  /// ignoring it.
  AgentProfile copyWith({
    int? schemaVersion,
    AgentIdentity? identity,
    AgentPersonality? personality,
    VoiceResponseBehavior? voiceBehavior,
    TurnTakingWords? turnTaking,
    List<AgentMemory>? memories,
    List<String>? vocabulary,
    List<MisheardWord>? misheard,
    List<String>? additionalInstructions,
  }) {
    return AgentProfile(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      identity: identity ?? this.identity,
      personality: personality ?? this.personality,
      voiceBehavior: voiceBehavior ?? this.voiceBehavior,
      turnTaking: turnTaking ?? this.turnTaking,
      memories: memories ?? this.memories,
      vocabulary: vocabulary ?? this.vocabulary,
      misheard: misheard ?? this.misheard,
      additionalInstructions:
          additionalInstructions ?? this.additionalInstructions,
    );
  }

  /// Schema version of the decoded profile.
  final int schemaVersion;

  /// Stable names and locale.
  final AgentIdentity identity;

  /// Interpersonal answer behavior.
  final AgentPersonality personality;

  /// Constraints for prose that may be spoken aloud.
  final VoiceResponseBehavior voiceBehavior;

  /// The user's own ways of taking and yielding the floor.
  final TurnTakingWords turnTaking;

  /// Who has the floor, as this profile decides it.
  ///
  /// Built here, once, rather than per utterance: `classify` runs on every
  /// partial transcript, which arrives a few times a second for as long as
  /// the microphone is open.
  final FloorControl floorControl;

  /// Structured facts eligible for deterministic selection.
  final List<AgentMemory> memories;

  /// Terms available to later ASR and transcript-refinement slices.
  final List<String> vocabulary;

  /// Words this recogniser gets wrong for this user, and what they were.
  ///
  /// Distinct from [vocabulary], which is a hint: it asks the recogniser to
  /// lean towards a word and the recogniser may do nothing with it — and on
  /// the corpus measured in `SpokenVocabularyBook`, did nothing at all.
  /// These are substitutions, applied to the transcript after the fact, and
  /// they put back exactly what the user said should have been there.
  final List<MisheardWord> misheard;

  /// Developer-authored instructions appended after bounded memories.
  final List<String> additionalInstructions;

  @override
  bool operator ==(Object other) =>
      other is AgentProfile &&
      other.schemaVersion == schemaVersion &&
      other.identity == identity &&
      other.personality == personality &&
      other.voiceBehavior == voiceBehavior &&
      other.turnTaking == turnTaking &&
      _listEquals(other.memories, memories) &&
      _listEquals(other.vocabulary, vocabulary) &&
      _listEquals(other.misheard, misheard) &&
      _listEquals(other.additionalInstructions, additionalInstructions);

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    identity,
    personality,
    voiceBehavior,
    turnTaking,
    Object.hashAll(memories),
    Object.hashAll(vocabulary),
    Object.hashAll(misheard),
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
