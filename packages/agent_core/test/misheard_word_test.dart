import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  group('a correction the user made once', () {
    test('is applied the next time the same thing is misheard', () {
      // The recogniser hears product names as the ordinary words they sound
      // like — `benchmarks/voice_eval` has 「Dart test」 coming back as
      // 「Dark text」 and 「Swift tests」 as 「sweep test」. Contextual biasing
      // is the textbook remedy and `SpokenVocabularyBook` records it
      // changing the transcript by not one character, so the remedy here is
      // the one that cannot fail to work: put back exactly what the user
      // said it should have been.
      const MisheardWord rule = MisheardWord(
        heard: 'Dark text',
        meant: 'Dart test',
      );

      expect(
        applyMisheardWords('跑一下 Dark text', <MisheardWord>[rule]),
        '跑一下 Dart test',
      );
    });

    test('does not fire inside a longer word', () {
      // Replacing every "cat" would rewrite "category". A rule is about a
      // word somebody said, not about a run of letters.
      const MisheardWord rule = MisheardWord(heard: 'cat', meant: 'cache');

      expect(
        applyMisheardWords('the category is cat', <MisheardWord>[rule]),
        'the category is cache',
      );
    });

    test('fires inside a Chinese sentence, which has no word breaks', () {
      // The boundary rule above cannot apply to Han: 「台中」 sits flush
      // against whatever follows it, so a rule that demanded a break would
      // never fire in the language this app is mostly used in.
      const MisheardWord rule = MisheardWord(heard: '台中天氣', meant: '台中天器');

      expect(
        applyMisheardWords('查一下台中天氣好嗎', <MisheardWord>[rule]),
        '查一下台中天器好嗎',
      );
    });

    test('matches however the recogniser capitalised it', () {
      const MisheardWord rule = MisheardWord(
        heard: 'flutter',
        meant: 'Flutter',
      );

      expect(
        applyMisheardWords('用 FLUTTER 寫的', <MisheardWord>[rule]),
        '用 Flutter 寫的',
      );
    });

    test('the longest rule wins when two of them overlap', () {
      // Otherwise the answer depends on what order the user happened to add
      // them in, which is not something they can reason about.
      const List<MisheardWord> rules = <MisheardWord>[
        MisheardWord(heard: 'dart', meant: 'Dart'),
        MisheardWord(heard: 'dart test', meant: 'Dart test'),
      ];

      expect(
        applyMisheardWords('run dart test now', rules),
        'run Dart test now',
      );
    });

    test('a rule that replaces something with itself is not a rule', () {
      const MisheardWord rule = MisheardWord(heard: 'same', meant: 'same');

      expect(
        applyMisheardWords('the same thing', <MisheardWord>[rule]),
        'the same thing',
      );
    });

    test('a blank rule cannot swallow the sentence', () {
      // A half-typed row in Settings must not turn every gap into a word.
      const List<MisheardWord> rules = <MisheardWord>[
        MisheardWord(heard: '', meant: 'nonsense'),
        MisheardWord(heard: '   ', meant: 'nonsense'),
      ];

      expect(applyMisheardWords('leave me alone', rules), 'leave me alone');
    });

    test('what a rule puts back is not fed to the other rules', () {
      // Two rules that chain would let a pair of innocent corrections
      // rewrite a sentence into something nobody asked for, and the result
      // would depend on their order.
      const List<MisheardWord> rules = <MisheardWord>[
        MisheardWord(heard: 'one', meant: 'two'),
        MisheardWord(heard: 'two', meant: 'three'),
      ];

      expect(applyMisheardWords('one', rules), 'two');
    });

    test('a mixed-script rule still respects the Latin end it has', () {
      // The first version asked whether the rule's first *and* last
      // character were Latin before checking anything, so every rule with
      // Han at one end — which is most of the ones this app is for — got no
      // boundary check at all and fired inside longer words.
      const MisheardWord rule = MisheardWord(
        heard: '台中 weather',
        meant: '台中天氣',
      );

      expect(
        applyMisheardWords('台中 weathers are nice', <MisheardWord>[rule]),
        '台中 weathers are nice',
      );
      expect(
        applyMisheardWords('台中 weather 如何', <MisheardWord>[rule]),
        '台中天氣 如何',
      );
    });

    test('a rule that begins in Latin does not start mid-word', () {
      const MisheardWord rule = MisheardWord(heard: 'open 台中', meant: '打開台中');

      expect(
        applyMisheardWords('reopen 台中', <MisheardWord>[rule]),
        'reopen 台中',
      );
    });

    test(
      'two rules of the same length do not depend on which was typed first',
      () {
        const MisheardWord lower = MisheardWord(heard: 'ios', meant: 'iOS');
        const MisheardWord upper = MisheardWord(heard: 'IOS', meant: 'iOS 版');

        expect(
          applyMisheardWords('ios and IOS', <MisheardWord>[lower, upper]),
          applyMisheardWords('ios and IOS', <MisheardWord>[upper, lower]),
        );
      },
    );

    test('a rule written in the exact case beats one that ignores it', () {
      const List<MisheardWord> rules = <MisheardWord>[
        MisheardWord(heard: 'ios', meant: 'wrong'),
        MisheardWord(heard: 'IOS', meant: 'iOS'),
      ];

      expect(applyMisheardWords('IOS', rules), 'iOS');
    });

    test(
      'an accented letter after a match is a word, however it is encoded',
      () {
        // Two encodings of the same word, and the boundary check used to get
        // both wrong in opposite directions: a decomposed 「é」 contains an
        // ASCII `e` and read as a word character, while a precomposed one
        // contains no ASCII at all and read as a break — so the rule fired
        // inside 「caté」 written the way most text actually arrives, leaving
        // the accent stranded on the replacement as `cacheé`.
        const MisheardWord rule = MisheardWord(heard: 'cat', meant: 'cache');

        // Decomposed: 'e' followed by a combining acute.
        expect(applyMisheardWords('caté', <MisheardWord>[rule]), 'caté');
        // Precomposed: one 'é'.
        expect(applyMisheardWords('caté', <MisheardWord>[rule]), 'caté');
      },
    );

    test(
      'a rule does not fire inside a word in an alphabet that has words',
      () {
        // The boundary test was ASCII-only, so every alphabet but Latin read
        // as a word break and let a rule land in the middle of a word.
        const MisheardWord rule = MisheardWord(heard: 'cat', meant: 'cache');

        // Cyrillic and Greek separate their words with spaces, so a letter
        // touching the match means the match is inside a longer word.
        expect(applyMisheardWords('catи', <MisheardWord>[rule]), 'catи');
        expect(applyMisheardWords('catα', <MisheardWord>[rule]), 'catα');
      },
    );

    test('kana after a match is not a word it is inside of', () {
      // Kana belongs with Han rather than with the alphabets above:
      // Japanese is written without spaces, so 「catの」 is the word followed
      // by a particle, not one longer word. Demanding a break here would
      // stop rules firing in exactly the languages this app is used in.
      const MisheardWord rule = MisheardWord(heard: 'cat', meant: 'cache');

      expect(applyMisheardWords('catの', <MisheardWord>[rule]), 'cacheの');
      expect(applyMisheardWords('cat的', <MisheardWord>[rule]), 'cache的');
    });

    test('a long rule is not beaten by a short one written in exact case', () {
      // Exact case breaks a tie between rules of the same length. It used to
      // be asked across the whole list first, which made case outrank length:
      // a four-letter rule took a span the nine-letter rule was written for.
      const List<MisheardWord> rules = <MisheardWord>[
        MisheardWord(heard: 'dart test', meant: 'Dart test'),
        MisheardWord(heard: 'DART', meant: 'X'),
      ];

      expect(applyMisheardWords('DART TEST', rules), 'Dart test');
    });

    test('a rule cannot land mid-word in what an earlier rule wrote', () {
      // The start boundary used to be read from the input, which is not what
      // precedes the match in the sentence actually being written.
      const List<MisheardWord> rules = <MisheardWord>[
        MisheardWord(heard: 'a-', meant: 'super'),
        MisheardWord(heard: 'cat', meant: 'cache'),
      ];

      expect(applyMisheardWords('a-cat', rules), 'supercat');
    });

    test('an emoji beside a match survives it', () {
      const MisheardWord rule = MisheardWord(
        heard: 'dark text',
        meant: 'Dart test',
      );

      expect(
        applyMisheardWords('好喔 🙂 dark text', <MisheardWord>[rule]),
        '好喔 🙂 Dart test',
      );
    });
  });
}
