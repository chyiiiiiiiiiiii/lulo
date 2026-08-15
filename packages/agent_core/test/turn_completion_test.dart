import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  group('TurnCompletion reads what the words say about being finished', () {
    test('an opening that announces a question is still in progress', () {
      expect(TurnCompletion.of('我想問的是'), TurnCompletion.continuing);
      expect(TurnCompletion.of('等一下'), TurnCompletion.continuing);
    });

    test('a question that has landed is settled', () {
      expect(TurnCompletion.of('這樣可以嗎'), TurnCompletion.settled);
      expect(TurnCompletion.of('明天天氣如何？'), TurnCompletion.settled);
    });

    test('a scrap too short to be finished says nothing either way', () {
      // A bare 「嗎」 is one misheard syllable, not a question, and shortening
      // the endpoint on a mishearing is how a user gets cut off mid-word.
      expect(TurnCompletion.of('嗎'), TurnCompletion.unknown);
      expect(TurnCompletion.of('好'), TurnCompletion.unknown);
    });

    test('plain unfinished words carry no signal', () {
      expect(TurnCompletion.of('介紹一下台北的天氣'), TurnCompletion.unknown);
    });

    test('nothing sayable is unknown rather than a crash', () {
      expect(TurnCompletion.of(''), TurnCompletion.unknown);
      expect(TurnCompletion.of('   '), TurnCompletion.unknown);
      expect(TurnCompletion.of('，。！'), TurnCompletion.unknown);
    });
  });

  group('the corpus ends where the endpointer thinks it does', () {
    // Ported whole from `macos/RunnerTests/SpeechTurnTests.swift`. This table
    // is the falsifiable half of the lexicon and the reason the Dart port can
    // be believed: it was read off the Swift classifier sentence by sentence,
    // so a port that disagrees with it anywhere has changed behaviour rather
    // than moved it. Two of the twelve groups — `short-answer-not-yet` and
    // `endpoint-thinking-pause` — are the 1.02s and 1.10s mid-utterance pauses
    // `docs/decisions/voice-turn-latency.md` measured running past the 0.8s
    // that submits a turn.
    const Map<String, TurnCompletion> cases = <String, TurnCompletion>{
      // short-answer-ready
      '好': TurnCompletion.unknown,
      '好，可以開始了。': TurnCompletion.settled,
      // short-answer-not-yet — the 1.02s mid-utterance pause
      '等一下': TurnCompletion.continuing,
      '等一下，還沒。': TurnCompletion.settled,
      // code-switch-product-names
      '我剛剛把 Flutter 跟 MLX 的版本都更新了。': TurnCompletion.settled,
      // code-switch-agent-tools
      '先用 Codex 檢查': TurnCompletion.unknown,
      '先用 Codex 檢查，再跑 Dart test。': TurnCompletion.settled,
      // numbers-date-time
      '八月二日下午三點半提醒我。': TurnCompletion.settled,
      // numbers-money-version
      '預算是一萬二': TurnCompletion.unknown,
      '預算是一萬二，版本先用三點五。': TurnCompletion.settled,
      // disfluency-self-correction
      '我想看明天': TurnCompletion.unknown,
      '我想看明天，欸不是': TurnCompletion.unknown,
      '我想看明天，欸不是，後天的天氣。': TurnCompletion.settled,
      // punctuation-natural-clauses
      '先回答核心': TurnCompletion.unknown,
      '先回答核心，細節我等等再補。': TurnCompletion.settled,
      // long-form-project-request
      '幫我先確認目前專案在哪個分支': TurnCompletion.unknown,
      '幫我先確認目前專案在哪個分支，測試有沒有通過': TurnCompletion.unknown,
      '幫我先確認目前專案在哪個分支，測試有沒有通過，再告訴我最值得先修的地方。': TurnCompletion.settled,
      // long-form-conversational
      '我不是要你全部重做': TurnCompletion.unknown,
      '我不是要你全部重做，我只是想知道現在這個版本': TurnCompletion.unknown,
      '我不是要你全部重做，我只是想知道現在這個版本，哪一段聽起來最不像臺灣人平常講話。': TurnCompletion.settled,
      // barge-in-stop-answer
      '等一下，先不要念完。': TurnCompletion.settled,
      // endpoint-thinking-pause — the 1.10s mid-utterance pause
      '我想問的是': TurnCompletion.continuing,
      '我想問的是……如果完全離線的話': TurnCompletion.continuing,
      '我想問的是……如果完全離線的話，記憶要怎麼同步？': TurnCompletion.settled,
    };

    for (final MapEntry<String, TurnCompletion> entry in cases.entries) {
      test('「${entry.key}」 reads as ${entry.value.name}', () {
        expect(TurnCompletion.of(entry.key), entry.value);
      });
    }

    test('no corpus sentence is held open after it ends', () {
      // The expensive mistake in the other direction: treating a finished
      // sentence as unfinished adds 0.6s to a turn that was already over.
      final Iterable<String> finished = cases.entries
          .where(
            (MapEntry<String, TurnCompletion> entry) =>
                entry.value == TurnCompletion.settled,
          )
          .map((MapEntry<String, TurnCompletion> entry) => entry.key);
      for (final String sentence in finished) {
        expect(
          TurnCompletion.of(sentence),
          isNot(TurnCompletion.continuing),
          reason: '「$sentence」 has finished and must not be waited out.',
        );
      }
    });
  });

  group("the user's own way of trailing off extends the built-in list", () {
    test('a filler nobody else uses holds the turn open once listed', () {
      expect(TurnCompletion.of('我的意思是說'), TurnCompletion.unknown);
      expect(
        TurnCompletion.of('我的意思是說', alsoUnfinished: <String>['我的意思是說']),
        TurnCompletion.continuing,
      );
      expect(
        TurnCompletion.of('欸那個我的意思是說', alsoUnfinished: <String>['我的意思是說']),
        TurnCompletion.continuing,
      );
    });

    test('the built-in list still applies alongside it', () {
      expect(
        TurnCompletion.of('然後', alsoUnfinished: <String>['我的意思是說']),
        TurnCompletion.continuing,
      );
      expect(
        TurnCompletion.of('這樣可以嗎', alsoUnfinished: <String>['我的意思是說']),
        TurnCompletion.settled,
      );
    });

    test('an empty entry is not a suffix of every sentence', () {
      // An empty entry is a suffix of every string, which would hold every
      // turn open for an extra 0.6s and read exactly like the model being
      // slow.
      expect(
        TurnCompletion.of('介紹一下台北的天氣', alsoUnfinished: <String>['', '   ']),
        TurnCompletion.unknown,
      );
    });
  });

  group('Latin endings are matched by word, not by suffix', () {
    test('a trailing connective holds the turn open', () {
      expect(
        TurnCompletion.of('tell me the weather and'),
        TurnCompletion.continuing,
      );
      expect(
        TurnCompletion.of('what I meant was um'),
        TurnCompletion.continuing,
      );
    });

    test('a word that merely ends in a connective does not', () {
      // "also" ends in "so" and is not a speaker trailing off.
      expect(
        TurnCompletion.of('the tests pass also'),
        isNot(TurnCompletion.continuing),
      );
    });
  });

  group('syllables measure speech rather than characters', () {
    test('a run of Latin letters is one syllable however long', () {
      // Counting characters instead makes "the" three times the utterance
      // that 「嗎」 is, which is backwards.
      expect(TurnCompletion.syllablesOf('Flutter'), 1);
      expect(TurnCompletion.syllablesOf('嗎'), 1);
    });

    test('each CJK character is its own syllable', () {
      expect(TurnCompletion.syllablesOf('這樣可以嗎'), 5);
    });

    test('punctuation and whitespace are not speech', () {
      // The comma the recogniser writes between clauses is not speech, and
      // counting it made a two-syllable scrap look long enough to shorten on.
      expect(TurnCompletion.syllablesOf('好，'), 1);
      expect(TurnCompletion.syllablesOf('先用 Codex 檢查'), 5);
    });
  });

  group('the required silence follows what was heard', () {
    const Duration endpoint = Duration(milliseconds: 800);

    test('an unfinished thought is given longer', () {
      // Sized to clear the corpus's longest mid-utterance pause: 0.8 + 0.6 is
      // 1.4s, against the 1.02s of `short-answer-not-yet`.
      expect(
        TurnCompletion.requiredSilence(after: '等一下', endpointSilence: endpoint),
        const Duration(milliseconds: 1400),
      );
    });

    test('a question that has landed is submitted sooner', () {
      expect(
        TurnCompletion.requiredSilence(
          after: '這樣可以嗎',
          endpointSilence: endpoint,
        ),
        const Duration(milliseconds: 550),
      );
    });

    test('words that say nothing either way wait the ordinary silence', () {
      expect(
        TurnCompletion.requiredSilence(
          after: '介紹一下台北的天氣',
          endpointSilence: endpoint,
        ),
        endpoint,
      );
    });

    test('a saving can never push the wait below zero', () {
      expect(
        TurnCompletion.requiredSilence(
          after: '這樣可以嗎',
          endpointSilence: const Duration(milliseconds: 100),
        ),
        Duration.zero,
      );
    });
  });
}
