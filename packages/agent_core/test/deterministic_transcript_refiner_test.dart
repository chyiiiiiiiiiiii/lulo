import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  final DeterministicTranscriptRefiner refiner =
      const DeterministicTranscriptRefiner();

  test('trims and removes whitespace only between adjacent CJK', () async {
    final TranscriptRefinement result = await refiner.refine(
      _request('  我 想 用   Flutter 開發  '),
    );

    expect(result.selectedTranscript, '我想用 Flutter 開發');
    expect(result.rawTranscript, '  我 想 用   Flutter 開發  ');
    expect(result.status, TranscriptRefinementStatus.applied);
    expect(result.edits.single.kind, TranscriptEditKind.whitespace);
  });

  test('corrects configured vocabulary as whole Latin tokens', () async {
    final TranscriptRefinement result = await refiner.refine(
      _request('flutter 跟 mlx，不是 html。', <String>['Flutter', 'MLX', 'ML']),
    );

    expect(result.selectedTranscript, 'Flutter 跟 MLX，不是 html。');
    expect(result.edits.single.kind, TranscriptEditKind.vocabulary);
  });

  test('does not guess ambiguous configured casing', () async {
    final TranscriptRefinement result = await refiner.refine(
      _request('使用 mlx', <String>['MLX', 'Mlx']),
    );

    expect(result.selectedTranscript, '使用 mlx');
    expect(result.status, TranscriptRefinementStatus.unchanged);
  });

  test('does not add punctuation remove fillers or convert script', () async {
    final TranscriptRefinement result = await refiner.refine(
      _request('欸我在台湾沒有問題'),
    );

    expect(result.selectedTranscript, '欸我在台湾沒有問題');
  });
}

TranscriptRefinementRequest _request(
  String raw, [
  List<String> vocabulary = const <String>[],
]) => TranscriptRefinementRequest(
  rawTranscript: raw,
  locale: 'zh-TW',
  protectedVocabulary: vocabulary,
  deadline: const Duration(milliseconds: 250),
);
