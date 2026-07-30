import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/agent_presence_frame_metrics.dart';

void main() {
  group('attributeAgentPresenceFrameSamples', () {
    test(
      'attributes delayed batches by timestamp with start-inclusive windows',
      () {
        final AgentPresenceFrameAttribution attribution =
            attributeAgentPresenceFrameSamples(
              windows: const <AgentPresenceFrameWindow>[
                AgentPresenceFrameWindow(
                  state: 'idle',
                  startMicrosInclusive: 100,
                  endMicrosExclusive: 200,
                ),
                AgentPresenceFrameWindow(
                  state: 'listening',
                  startMicrosInclusive: 200,
                  endMicrosExclusive: 300,
                ),
              ],
              frames: const <AgentPresenceRawFrameSample>[
                AgentPresenceRawFrameSample(
                  timestampMicros: 250,
                  buildMicros: 2,
                  rasterMicros: 3,
                ),
                AgentPresenceRawFrameSample(
                  timestampMicros: 150,
                  buildMicros: 4,
                  rasterMicros: 5,
                ),
                AgentPresenceRawFrameSample(
                  timestampMicros: 200,
                  buildMicros: 6,
                  rasterMicros: 7,
                ),
                AgentPresenceRawFrameSample(
                  timestampMicros: 300,
                  buildMicros: 8,
                  rasterMicros: 9,
                ),
              ],
            );

        expect(
          attribution
              .framesFor('idle')
              .map(
                (AgentPresenceRawFrameSample frame) => frame.timestampMicros,
              ),
          <int>[150],
        );
        expect(
          attribution
              .framesFor('listening')
              .map(
                (AgentPresenceRawFrameSample frame) => frame.timestampMicros,
              ),
          <int>[200, 250],
        );
        expect(attribution.assignedFrameCount, 3);
        expect(attribution.unassignedFrameCount, 1);
      },
    );

    test('serializes aligned compact arrays without verbose frame maps', () {
      final Map<String, Object?> report = serializeAgentPresenceStateFrames(
        window: const AgentPresenceFrameWindow(
          state: 'idle',
          startMicrosInclusive: 100,
          endMicrosExclusive: 200,
        ),
        frames: const <AgentPresenceRawFrameSample>[
          AgentPresenceRawFrameSample(
            timestampMicros: 120,
            buildMicros: 2,
            rasterMicros: 3,
          ),
          AgentPresenceRawFrameSample(
            timestampMicros: 180,
            buildMicros: 4,
            rasterMicros: 5,
          ),
        ],
      );

      expect(report['frame_timestamps_micros'], <int>[120, 180]);
      expect(report['build_times_micros'], <int>[2, 4]);
      expect(report['raster_times_micros'], <int>[3, 5]);
      expect(report, isNot(contains('frames')));
    });

    test('bounds a six by 1200 frame report and round-trips every sample', () {
      final Map<String, Object?> report = <String, Object?>{
        'states': <Object?>[
          for (var state = 0; state < 6; state += 1)
            serializeAgentPresenceStateFrames(
              window: AgentPresenceFrameWindow(
                state: 'state_$state',
                startMicrosInclusive: state * 10000000,
                endMicrosExclusive: (state + 1) * 10000000,
              ),
              frames: <AgentPresenceRawFrameSample>[
                for (var frame = 0; frame < 1200; frame += 1)
                  AgentPresenceRawFrameSample(
                    timestampMicros: state * 10000000 + frame * 8000,
                    buildMicros: 400 + frame % 20,
                    rasterMicros: 700 + frame % 30,
                  ),
              ],
            ),
        ],
      };
      final String encoded = jsonEncode(report);
      final Object? decoded = jsonDecode(encoded);
      final String reencoded = jsonEncode(decoded);
      final Map<String, dynamic> roundTrip = decoded! as Map<String, dynamic>;
      final List<dynamic> states = roundTrip['states']! as List<dynamic>;
      final int roundTripFrameCount = states.fold<int>(
        0,
        (int count, dynamic state) =>
            count +
            ((state as Map<String, dynamic>)['frame_timestamps_micros']!
                    as List<dynamic>)
                .length,
      );

      expect(utf8.encode(encoded).length, lessThan(300000));
      expect(reencoded, encoded);
      expect(roundTripFrameCount, 7200);
    });
  });

  group('evaluateAgentPresenceFrameReport', () {
    test('accepts only the exact hardware evidence protocol', () {
      final AgentPresenceFrameEvaluation evaluation =
          evaluateAgentPresenceFrameReport(_validReport());

      expect(evaluation.protocolValid, isTrue);
      expect(evaluation.isAccepted, isTrue);
    });

    for (final ({String name, void Function(Map<String, Object?>) mutate})
        protocolMutation
        in <({String name, void Function(Map<String, Object?>) mutate})>[
          (
            name: 'schema version',
            mutate: (Map<String, Object?> report) =>
                report['schema_version'] = 2,
          ),
          (
            name: 'evidence kind',
            mutate: (Map<String, Object?> report) =>
                report['evidence_kind'] = 'smoke',
          ),
          (
            name: 'build mode',
            mutate: (Map<String, Object?> report) =>
                _metadata(report)['build_mode'] = 'release',
          ),
          (
            name: 'renderer',
            mutate: (Map<String, Object?> report) =>
                _metadata(report)['renderer'] = 'Skia',
          ),
          (
            name: 'refresh rate',
            mutate: (Map<String, Object?> report) =>
                _metadata(report)['display_refresh_hz'] = 60.0,
          ),
          (
            name: 'warmup duration',
            mutate: (Map<String, Object?> report) =>
                _metadata(report)['warmup_duration_ms'] = 1999,
          ),
          (
            name: 'state duration',
            mutate: (Map<String, Object?> report) =>
                _metadata(report)['state_duration_ms'] = 9999,
          ),
          (
            name: 'shader path',
            mutate: (Map<String, Object?> report) =>
                _metadata(report)['shader_path'] = 'fallback',
          ),
          (
            name: 'shader readiness',
            mutate: (Map<String, Object?> report) =>
                _metadata(report)['shader_compile_ready'] = false,
          ),
          (
            name: 'physical resolution',
            mutate: (Map<String, Object?> report) =>
                _metadata(report).remove('physical_display_resolution'),
          ),
          (
            name: 'test surface resolution',
            mutate: (Map<String, Object?> report) =>
                _metadata(report).remove('test_surface_resolution'),
          ),
          (
            name: 'placeholder machine',
            mutate: (Map<String, Object?> report) =>
                _metadata(report)['machine'] = 'unknown',
          ),
          (
            name: 'duplicate state',
            mutate: (Map<String, Object?> report) {
              final List<Object?> states = report['states']! as List<Object?>;
              states.add(Map<String, Object?>.from(states.first! as Map));
            },
          ),
          (
            name: 'missing state',
            mutate: (Map<String, Object?> report) {
              final List<Object?> states = report['states']! as List<Object?>;
              states.removeLast();
            },
          ),
          (
            name: 'misaligned frame timestamps',
            mutate: (Map<String, Object?> report) {
              final List<Object?> states = report['states']! as List<Object?>;
              final Map<String, Object?> first =
                  states.first! as Map<String, Object?>;
              first['frame_timestamps_micros'] = <Object?>[100];
            },
          ),
        ]) {
      test('rejects mutated ${protocolMutation.name} protocol', () {
        final Map<String, Object?> report = _validReport();
        protocolMutation.mutate(report);

        final AgentPresenceFrameEvaluation evaluation =
            evaluateAgentPresenceFrameReport(report);

        expect(evaluation.protocolValid, isFalse);
        expect(evaluation.isAccepted, isFalse);
      });
    }

    test('smoke reports can collect samples but can never be accepted', () {
      final Map<String, Object?> report = _validReport();
      report['evidence_kind'] = 'smoke';

      final AgentPresenceFrameEvaluation evaluation =
          evaluateAgentPresenceFrameReport(report);

      expect(evaluation.hasSufficientSamples, isTrue);
      expect(evaluation.isAccepted, isFalse);
    });

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
        960,
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
    'schema_version': 1,
    'evidence_kind': 'hardware_profile',
    'metadata': <String, Object?>{
      'renderer': 'Impeller/Metal',
      'flutter_version': '3.44.1',
      'dart_version': '3.12.1',
      'build_mode': 'profile',
      'macos_version': '26.5.1',
      'device': 'macOS',
      'display_model': 'Built-in Liquid Retina XDR',
      'display_refresh_hz': 120.0,
      'physical_display_resolution': '3024x1964',
      'test_surface_resolution': '1600x1200',
      'display_scale': 2.0,
      'power_mode': 'AC, Low Power Mode off',
      'machine': 'M1 Pro, 32 GB',
      'ambient_workload': 'controlled',
      'warmup_duration_ms': 2000,
      'state_duration_ms': 10000,
      'shader_path': 'fragmentProgram',
      'shader_compile_ready': true,
    },
    'states': <Object?>[
      for (final (int index, String state) in <String>[
        'idle',
        'listening',
        'thinking',
        'speaking',
        'working',
        'error',
      ].indexed)
        <String, Object?>{
          'state': state,
          'window_start_micros_inclusive': index * 10000000,
          'window_end_micros_exclusive': (index + 1) * 10000000,
          'frame_timestamps_micros': <Object?>[
            for (var sample = 0; sample < 960; sample += 1)
              index * 10000000 + sample * 10000,
          ],
          'build_times_micros': <Object?>[...List<Object?>.filled(960, 1000)],
          'raster_times_micros': <Object?>[...List<Object?>.filled(960, 1000)],
        },
    ],
    'attribution': <String, Object?>{
      'timestamp_phase': 'buildStart',
      'window_policy': 'startInclusive_endExclusive',
      'assigned_frame_count': 5760,
      'unassigned_frame_count': 0,
    },
  };
}

Map<String, Object?> _metadata(Map<String, Object?> report) =>
    report['metadata']! as Map<String, Object?>;

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
