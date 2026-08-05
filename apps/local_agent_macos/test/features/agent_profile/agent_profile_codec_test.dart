import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/agent_profile/agent_profile_codec.dart';

void main() {
  test('the words the user takes and yields the floor with are read', () {
    final AgentProfileDecodeResult result = decodeAgentProfile(
      <String, Object?>{
        'schemaVersion': 1,
        'turnTaking': <String, Object?>{
          'acknowledgements': <Object?>['蛤', '真的假的喔'],
          'corrections': <Object?>['先停'],
          'unfinished': <Object?>['我的意思是說'],
        },
      },
    );

    expect(result.error, isNull);
    expect(result.profile.turnTaking.acknowledgements, <String>['蛤', '真的假的喔']);
    expect(result.profile.turnTaking.corrections, <String>['先停']);
    expect(result.profile.turnTaking.unfinished, <String>['我的意思是說']);
    expect(result.profile.floorControl.classify('蛤蛤'), FloorClaim.backchannel);
    expect(result.profile.floorControl.classify('先停'), FloorClaim.correction);
  });

  test('a profile with no turnTaking section keeps the built-in policy', () {
    final AgentProfileDecodeResult result = decodeAgentProfile(
      <String, Object?>{'schemaVersion': 1},
    );

    expect(result.profile.turnTaking, const TurnTakingWords());
    expect(result.profile.floorControl.classify('嗯嗯'), FloorClaim.backchannel);
  });

  test('a malformed turnTaking section is ignored rather than fatal', () {
    // The whole codec is defensive: a developer editing this file by hand
    // must not be able to make the agent refuse to start.
    final AgentProfileDecodeResult result = decodeAgentProfile(
      <String, Object?>{
        'schemaVersion': 1,
        'turnTaking': <String, Object?>{
          'acknowledgements': 'not a list',
          'corrections': <Object?>[42, '先停', null],
        },
      },
    );

    expect(result.error, isNull);
    expect(result.profile.turnTaking.acknowledgements, isEmpty);
    expect(result.profile.turnTaking.corrections, <String>['先停']);
  });
  test('decodes the complete developer profile schema', () {
    final AgentProfileDecodeResult result = decodeAgentProfile(
      <String, Object?>{
        'schemaVersion': 1,
        'identity': <String, Object?>{
          'agentName': 'Lulo',
          'userName': 'Yii',
          'locale': 'zh-TW',
        },
        'personality': <String, Object?>{
          'tone': '親近但不裝熟',
          'responseLength': 'balanced',
          'admitUncertainty': true,
          'leadWithAnswer': true,
        },
        'voiceBehavior': <String, Object?>{
          'avoidMarkdown': true,
          'avoidReadingUrls': true,
          'avoidLongLists': true,
          'preferNaturalShortSentences': true,
        },
        'memories': <Object?>[
          <String, Object?>{
            'id': 'project-lulo',
            'kind': 'project',
            'content': 'Yii 正在開發 Lulo。',
            'triggers': <Object?>['Lulo'],
            'enabled': true,
          },
        ],
        'vocabulary': <Object?>['Flutter', 'MLX'],
        'additionalInstructions': <Object?>['不要空泛稱讚。'],
      },
    );

    expect(result.error, isNull);
    expect(result.profile.identity.userName, 'Yii');
    expect(
      result.profile.personality.responseLength,
      AgentResponseLength.balanced,
    );
    expect(result.profile.memories.single.id, 'project-lulo');
    expect(result.profile.vocabulary, <String>['Flutter', 'MLX']);
    expect(result.profile.additionalInstructions, <String>['不要空泛稱讚。']);
  });

  test('unknown fields and enum values use built-in defaults', () {
    final AgentProfileDecodeResult result = decodeAgentProfile(
      <String, Object?>{
        'schemaVersion': 1,
        'future': 'ignored',
        'personality': <String, Object?>{'responseLength': 'instant'},
      },
    );

    expect(result.error, isNull);
    expect(
      result.profile.personality.responseLength,
      AgentResponseLength.concise,
    );
  });

  test('invalid memories are skipped without losing valid memories', () {
    final AgentProfileDecodeResult result = decodeAgentProfile(
      <String, Object?>{
        'schemaVersion': 1,
        'memories': <Object?>[
          <String, Object?>{'id': 'bad', 'kind': 'project', 'content': ''},
          <String, Object?>{
            'id': 'good',
            'kind': 'preference',
            'content': '偏好簡短回答。',
          },
        ],
      },
    );

    expect(result.error, isNull);
    expect(result.skippedMemoryIds, <String>['bad']);
    expect(result.profile.memories.single.id, 'good');
  });

  test('invalid roots and unsupported schemas return a non-fatal error', () {
    final AgentProfileDecodeResult invalid = decodeAgentProfile('not a map');
    final AgentProfileDecodeResult future = decodeAgentProfile(
      <String, Object?>{'schemaVersion': 2},
    );

    expect(invalid.profile, AgentProfile.builtIn());
    expect(invalid.error, isNotNull);
    expect(future.profile, AgentProfile.builtIn());
    expect(future.error, contains('schemaVersion'));
  });
}
