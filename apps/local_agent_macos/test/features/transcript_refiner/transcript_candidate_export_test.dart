import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/transcript_refiner/transcript_candidate_export.dart';

void main() {
  test('builds a stable voice-eval candidate without hiding raw text', () {
    final Map<String, Object?> candidate = buildTranscriptCandidateExport(
      runId: 'deterministic-refiner-v1',
      adapterName: 'lulo-deterministic-refiner',
      adapterVersion: '1',
      corpusId: 'zh-TW-v1',
      refinements: <String, TranscriptRefinement>{
        'z-last': _refinement('原始二', '修訂二'),
        'a-first': _refinement('原始一', '修訂一'),
      },
    );

    expect(candidate['schemaVersion'], 1);
    expect(candidate['kind'], 'transcript');
    expect(candidate['runId'], 'deterministic-refiner-v1');
    expect(candidate['corpusId'], 'zh-TW-v1');
    expect(candidate['adapter'], <String, Object?>{
      'name': 'lulo-deterministic-refiner',
      'version': '1',
    });
    expect(candidate['cases'], <Map<String, Object?>>[
      <String, Object?>{
        'caseId': 'a-first',
        'rawTranscript': '原始一',
        'refinedTranscript': '修訂一',
        'partialEvents': <Object?>[],
        'finalAtMs': 0,
      },
      <String, Object?>{
        'caseId': 'z-last',
        'rawTranscript': '原始二',
        'refinedTranscript': '修訂二',
        'partialEvents': <Object?>[],
        'finalAtMs': 0,
      },
    ]);
  });

  test('omits a refined transcript when raw text was selected', () {
    final Map<String, Object?> candidate = buildTranscriptCandidateExport(
      runId: 'safe-fallback',
      adapterName: 'lulo-refiner',
      adapterVersion: '1',
      corpusId: 'zh-TW-v1',
      refinements: <String, TranscriptRefinement>{
        'fallback': _refinement(
          '保留原文',
          null,
          status: TranscriptRefinementStatus.rejected,
        ),
      },
    );

    final Map<String, Object?> exportedCase =
        (candidate['cases'] as List<Object?>).single as Map<String, Object?>;
    expect(exportedCase['rawTranscript'], '保留原文');
    expect(exportedCase.containsKey('refinedTranscript'), isFalse);
  });
}

TranscriptRefinement _refinement(
  String raw,
  String? proposed, {
  TranscriptRefinementStatus status = TranscriptRefinementStatus.applied,
}) => TranscriptRefinement(
  rawTranscript: raw,
  proposedTranscript: proposed,
  selectedTranscript: proposed ?? raw,
  status: status,
  edits: const <TranscriptEdit>[],
  rejectionReasons: const <TranscriptRejectionReason>[],
  refinerId: 'deterministic',
  refinerVersion: '1',
  elapsed: const Duration(milliseconds: 2),
);
