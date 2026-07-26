import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/agent_presence_frame_metrics.dart';

void main() {
  group('evaluateAgentPresenceFrameReport', () {
    test(
      'accepts complete per-state build and raster samples at every gate',
      () {
        final AgentPresenceFrameEvaluation evaluation =
            evaluateAgentPresenceFrameReport(_validReport());

        expect(evaluation.isAccepted, isTrue);
        expect(evaluation.metadataComplete, isTrue);
        expect(evaluation.hasSufficientSamples, isTrue);
        expect(evaluation.stageEvaluations, hasLength(12));
        expect(
          evaluation.stageEvaluations.every(
            (AgentPresenceStageEvaluation stage) => stage.meetsTimingGates,
          ),
          isTrue,
        );
      },
    );

    test('rejects empty build or raster samples independently', () {
      final Map<String, Object?> report = _validReport();
      final List<Object?> states = report['states']! as List<Object?>;
      final Map<String, Object?> listening = states[1]! as Map<String, Object?>;
      listening['raster_times_micros'] = <Object?>[];

      final AgentPresenceFrameEvaluation evaluation =
          evaluateAgentPresenceFrameReport(report);

      expect(evaluation.isAccepted, isFalse);
      expect(
        evaluation.stageFor('listening', AgentPresenceFrameStage.raster).count,
        0,
      );
      expect(
        evaluation.stageFor('listening', AgentPresenceFrameStage.build).count,
        10,
      );
    });

    for (final String key in <String>[
      'renderer',
      'flutter_version',
      'dart_version',
      'build_mode',
      'macos_version',
      'device',
      'display_model',
      'display_refresh_hz',
      'power_mode',
      'machine',
    ]) {
      test('rejects missing $key metadata', () {
        final Map<String, Object?> report = _validReport();
        final Map<String, Object?> metadata =
            report['metadata']! as Map<String, Object?>;
        metadata.remove(key);

        final AgentPresenceFrameEvaluation evaluation =
            evaluateAgentPresenceFrameReport(report);

        expect(evaluation.metadataComplete, isFalse);
        expect(evaluation.isAccepted, isFalse);
      });
    }

    test('rejects insufficient post-warmup build samples', () {
      final Map<String, Object?> report = _validReport();
      final Map<String, Object?> metadata =
          report['metadata']! as Map<String, Object?>;
      metadata['display_refresh_hz'] = 2.0;
      final List<Object?> states = report['states']! as List<Object?>;
      final Map<String, Object?> idle = states.first! as Map<String, Object?>;
      idle['build_times_micros'] = <Object?>[
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
        1000,
      ];

      final AgentPresenceFrameEvaluation evaluation =
          evaluateAgentPresenceFrameReport(report);

      expect(evaluation.minimumSamplesPerStagePerState, 16);
      expect(evaluation.hasSufficientSamples, isFalse);
      expect(evaluation.isAccepted, isFalse);
    });

    test(
      'uses nearest-rank percentiles and rejects build p95 above 8.33 ms',
      () {
        final Map<String, Object?> report = _validReport();
        _replaceSamples(
          report,
          state: 'thinking',
          stage: AgentPresenceFrameStage.build,
          samples: <int>[...List<int>.filled(18, 1000), 8331, 12000],
        );

        final AgentPresenceFrameEvaluation evaluation =
            evaluateAgentPresenceFrameReport(report);
        final AgentPresenceStageEvaluation build = evaluation.stageFor(
          'thinking',
          AgentPresenceFrameStage.build,
        );

        expect(build.p95Millis, closeTo(8.331, 0.000001));
        expect(build.p99Millis, 12);
        expect(build.meetsTimingGates, isFalse);
        expect(evaluation.isAccepted, isFalse);
      },
    );

    test('rejects raster p99 above 12 ms without combining stages', () {
      final Map<String, Object?> report = _validReport();
      _replaceSamples(
        report,
        state: 'speaking',
        stage: AgentPresenceFrameStage.raster,
        samples: <int>[...List<int>.filled(98, 1000), 12001, 12001],
      );

      final AgentPresenceFrameEvaluation evaluation =
          evaluateAgentPresenceFrameReport(report);

      expect(
        evaluation
            .stageFor('speaking', AgentPresenceFrameStage.raster)
            .p99Millis,
        closeTo(12.001, 0.000001),
      );
      expect(
        evaluation
            .stageFor('speaking', AgentPresenceFrameStage.raster)
            .meetsTimingGates,
        isFalse,
      );
      expect(
        evaluation
            .stageFor('speaking', AgentPresenceFrameStage.build)
            .meetsTimingGates,
        isTrue,
      );
      expect(evaluation.isAccepted, isFalse);
    });

    test('rejects any build or raster sample above 24 ms', () {
      final Map<String, Object?> report = _validReport();
      _replaceSamples(
        report,
        state: 'working',
        stage: AgentPresenceFrameStage.raster,
        samples: <int>[...List<int>.filled(99, 1000), 24001],
      );

      final AgentPresenceFrameEvaluation evaluation =
          evaluateAgentPresenceFrameReport(report);
      final AgentPresenceStageEvaluation raster = evaluation.stageFor(
        'working',
        AgentPresenceFrameStage.raster,
      );

      expect(raster.maximumMillis, closeTo(24.001, 0.000001));
      expect(raster.hasNoSampleAbove24Millis, isFalse);
      expect(evaluation.isAccepted, isFalse);
    });

    test(
      'allows one percent but rejects more than one percent over 16.67 ms',
      () {
        final Map<String, Object?> accepted = _validReport();
        _replaceSamples(
          accepted,
          state: 'error',
          stage: AgentPresenceFrameStage.build,
          samples: <int>[...List<int>.filled(99, 1000), 17000],
        );
        final Map<String, Object?> rejected = _validReport();
        _replaceSamples(
          rejected,
          state: 'error',
          stage: AgentPresenceFrameStage.build,
          samples: <int>[...List<int>.filled(198, 1000), 17000, 17000],
        );

        final AgentPresenceStageEvaluation acceptedBuild =
            evaluateAgentPresenceFrameReport(
              accepted,
            ).stageFor('error', AgentPresenceFrameStage.build);
        final AgentPresenceFrameEvaluation rejectedEvaluation =
            evaluateAgentPresenceFrameReport(rejected);
        final AgentPresenceStageEvaluation rejectedBuild = rejectedEvaluation
            .stageFor('error', AgentPresenceFrameStage.build);

        expect(acceptedBuild.over16Point67Ratio, 0.01);
        expect(acceptedBuild.hasAtMostOnePercentOver16Point67Millis, isTrue);
        expect(rejectedBuild.over16Point67Ratio, 0.01);
        expect(rejectedBuild.over16Point67Count, 2);
        expect(rejectedBuild.hasAtMostOnePercentOver16Point67Millis, isTrue);

        _replaceSamples(
          rejected,
          state: 'error',
          stage: AgentPresenceFrameStage.build,
          samples: <int>[...List<int>.filled(197, 1000), 17000, 17000, 17000],
        );
        final AgentPresenceStageEvaluation tooMany =
            evaluateAgentPresenceFrameReport(
              rejected,
            ).stageFor('error', AgentPresenceFrameStage.build);
        expect(tooMany.over16Point67Ratio, 0.015);
        expect(tooMany.hasAtMostOnePercentOver16Point67Millis, isFalse);
      },
    );
  });
}

Map<String, Object?> _validReport() {
  return <String, Object?>{
    'metadata': <String, Object?>{
      'renderer': 'Impeller',
      'flutter_version': '3.44.1',
      'dart_version': '3.12.1',
      'build_mode': 'profile',
      'macos_version': '26.5.1',
      'device': 'macOS',
      'display_model': 'test display',
      'display_refresh_hz': 1.0,
      'display_resolution': '3024x1964',
      'display_scale': 2.0,
      'power_mode': 'AC, Low Power Mode off',
      'machine': 'M1 Pro, 32 GB',
      'ambient_workload': 'controlled',
      'warmup_duration_ms': 2000,
      'state_duration_ms': 10000,
    },
    'states': <Object?>[
      for (final String state in <String>[
        'idle',
        'listening',
        'thinking',
        'speaking',
        'working',
        'error',
      ])
        <String, Object?>{
          'state': state,
          'build_times_micros': <Object?>[
            1000,
            1000,
            1000,
            1000,
            1000,
            1000,
            1000,
            1000,
            1000,
            1000,
          ],
          'raster_times_micros': <Object?>[
            1000,
            1000,
            1000,
            1000,
            1000,
            1000,
            1000,
            1000,
            1000,
            1000,
          ],
        },
    ],
  };
}

void _replaceSamples(
  Map<String, Object?> report, {
  required String state,
  required AgentPresenceFrameStage stage,
  required List<int> samples,
}) {
  final List<Object?> states = report['states']! as List<Object?>;
  final Map<String, Object?> stateReport = states
      .cast<Map<String, Object?>>()
      .singleWhere(
        (Map<String, Object?> candidate) => candidate['state'] == state,
      );
  stateReport[switch (stage) {
    AgentPresenceFrameStage.build => 'build_times_micros',
    AgentPresenceFrameStage.raster => 'raster_times_micros',
  }] = samples
      .cast<Object?>();
}
