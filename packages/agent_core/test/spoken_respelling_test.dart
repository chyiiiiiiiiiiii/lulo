import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

/// What the synthesiser is handed, which is not what anybody reads.
void main() {
  const List<SpokenRespelling> table = <SpokenRespelling>[
    SpokenRespelling(word: '企業', saidAs: '氣業'),
    SpokenRespelling(word: '結構', saidAs: '潔構'),
  ];

  test('a word the voice mangles goes out spelled another way', () {
    expect(respellForSpeech('這家企業的結構很奇怪', table), '這家氣業的潔構很奇怪');
  });

  test('a sentence with none of them is handed over untouched', () {
    expect(respellForSpeech('今天天氣不錯', table), '今天天氣不錯');
    expect(respellForSpeech('今天天氣不錯', const <SpokenRespelling>[]), '今天天氣不錯');
  });

  test('what one rule writes is never read by the next', () {
    // Otherwise a table would rewrite itself into something nobody typed,
    // and the result would depend on the order the rows were added in.
    expect(
      respellForSpeech('企業', const <SpokenRespelling>[
        SpokenRespelling(word: '企業', saidAs: '氣業'),
        SpokenRespelling(word: '氣業', saidAs: '完全不同'),
      ]),
      '氣業',
    );
  });

  test('the longer word wins where two rules could both fire', () {
    expect(
      respellForSpeech('企業文化', const <SpokenRespelling>[
        SpokenRespelling(word: '企業', saidAs: '氣業'),
        SpokenRespelling(word: '企業文化', saidAs: '氣業文話'),
      ]),
      '氣業文話',
    );
  });

  test('a half-typed row does nothing', () {
    // A blank word would match between every pair of characters, and a row
    // that respells something as itself is one somebody started and left.
    expect(
      respellForSpeech('企業', const <SpokenRespelling>[
        SpokenRespelling(word: '', saidAs: '氣業'),
        SpokenRespelling(word: '企業', saidAs: '企業'),
      ]),
      '企業',
    );
  });

  test('a Latin rule does not fire inside a longer word', () {
    expect(
      respellForSpeech('Flutter and flu', const <SpokenRespelling>[
        SpokenRespelling(word: 'flu', saidAs: 'floo'),
      ]),
      'Flutter and floo',
    );
  });

  test('usable says which rows can do anything', () {
    expect(const SpokenRespelling(word: '企業', saidAs: '氣業').isUsable, isTrue);
    expect(const SpokenRespelling(word: ' ', saidAs: '氣業').isUsable, isFalse);
    expect(const SpokenRespelling(word: '企業', saidAs: '企業').isUsable, isFalse);
  });
}
