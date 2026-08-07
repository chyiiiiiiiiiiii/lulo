import 'dart:convert';

import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/agent_profile/agent_profile_codec.dart';

/// Writing the profile back out, so the user can change it from the app.
///
/// The file was only ever read. Everything in it — the agent's name, how it
/// talks, what it remembers, which words take and yield the floor — could
/// therefore only be changed by opening a JSON file in a text editor, which
/// no release user is going to do. Encoding has one hard requirement: what
/// comes back must be what went in, including the fields the screen does not
/// show, or saving one setting would quietly drop the rest.
void main() {
  test('a profile survives being written and read back', () {
    final AgentProfile written = AgentProfile(
      identity: const AgentIdentity(
        agentName: '露露',
        userName: 'Yii',
        locale: 'zh-TW',
      ),
      personality: const AgentPersonality(
        tone: '直接一點，不要客套',
        responseLength: AgentResponseLength.detailed,
        admitUncertainty: false,
        leadWithAnswer: false,
      ),
      voiceBehavior: const VoiceResponseBehavior(
        avoidMarkdown: false,
        avoidReadingUrls: true,
        avoidLongLists: false,
        preferNaturalShortSentences: true,
      ),
      turnTaking: const TurnTakingWords(
        acknowledgements: <String>['蛤', '嗯哼'],
        corrections: <String>['先停'],
        unfinished: <String>['然後'],
      ),
      memories: <AgentMemory>[
        AgentMemory(
          id: 'home',
          kind: AgentMemoryKind.personal,
          content: '住在台中',
          triggers: <String>['台中', '天氣'],
        ),
        AgentMemory(
          id: 'off',
          kind: AgentMemoryKind.preference,
          content: '不要用條列',
          enabled: false,
        ),
      ],
      vocabulary: <String>['Lulo', 'LiteRT'],
      additionalInstructions: <String>['回答用繁體中文'],
    );

    final AgentProfileDecodeResult read = decodeAgentProfile(
      encodeAgentProfile(written),
    );

    expect(read.error, isNull);
    expect(read.skippedMemoryIds, isEmpty);
    expect(read.profile, written);
  });

  test('the built-in profile survives the same trip', () {
    // The vocabulary is the trap: the decoder reads a missing list as empty
    // rather than as the built-in one, so an encoder that left it out would
    // strip the recogniser's own terms the first time the user changed their
    // name.
    final AgentProfile written = AgentProfile.builtIn();

    final AgentProfileDecodeResult read = decodeAgentProfile(
      encodeAgentProfile(written),
    );

    expect(read.profile, written);
    expect(read.profile.vocabulary, builtInVocabulary);
  });

  test('what is written is plain JSON', () {
    // It is still a file a developer edits by hand, and it still has to be
    // readable by the store that reads it now.
    final Map<String, Object?> encoded = encodeAgentProfile(
      AgentProfile.builtIn(),
    );

    expect(encoded['schemaVersion'], 1);
    expect(encoded['identity'], isA<Map<String, Object?>>());
    expect(encoded['memories'], isA<List<Object?>>());
  });

  test('corrections survive a trip through the file', () {
    // `encodeAgentProfile` has to write every field, because the decoder
    // reads a missing list as empty — a correction that vanished on the
    // next launch would be a lesson the user has to teach twice.
    final AgentProfile profile = AgentProfile(
      misheard: const <MisheardWord>[
        MisheardWord(heard: 'Dark text', meant: 'Dart test'),
        MisheardWord(heard: '台中天氣', meant: '台中天器'),
      ],
    );

    final AgentProfileDecodeResult back = decodeAgentProfile(
      jsonDecode(jsonEncode(encodeAgentProfile(profile)))
          as Map<String, Object?>,
    );

    expect(back.profile.misheard, profile.misheard);
  });

  test('a malformed correction is dropped rather than read as blank', () {
    // A hand-edited file with a row missing its left-hand side would match
    // between every pair of characters in every transcript and rewrite
    // everything the user says.
    final AgentProfileDecodeResult back = decodeAgentProfile(<String, Object?>{
      'schemaVersion': 1,
      'misheard': <Object?>[
        <String, Object?>{'meant': 'Dart test'},
        <String, Object?>{'heard': '', 'meant': 'nonsense'},
        'not a row at all',
        <String, Object?>{'heard': 'Dark text', 'meant': 'Dart test'},
      ],
    });

    expect(back.profile.misheard, <MisheardWord>[
      const MisheardWord(heard: 'Dark text', meant: 'Dart test'),
    ]);
  });
}
