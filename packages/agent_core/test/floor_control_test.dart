import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  _spokenForGroup();
  _ownWordsGroup();
  group('FloorControl.classify', () {
    test('hears the listening noises as backchannel', () {
      for (final String heard in <String>[
        '嗯',
        '嗯嗯',
        '嗯嗯嗯',
        '對',
        '對對',
        '對對對',
        '對啊',
        '好',
        '好的',
        '好喔',
        '是',
        '是喔',
        '喔',
        '哦哦',
        '哈哈',
        '哈哈哈',
        '了解',
        '我知道',
        '原來如此',
        '沒錯',
        'OK',
        'ok',
        'okay',
        'yeah',
        'right',
        'I see',
        'got it',
        'uh-huh',
      ]) {
        expect(
          FloorControl().classify(heard),
          FloorClaim.backchannel,
          reason: '"$heard" is how a listener says carry on.',
        );
      }
    });

    test('hears the corrections as taking the floor back', () {
      for (final String heard in <String>[
        '不對',
        '不是',
        '不是啦',
        '等等',
        '等一下',
        '等下',
        '停',
        '停一下',
        '錯了',
        '不要',
        '夠了',
        '重來',
        'wait',
        'stop',
        'hold on',
        'no no',
      ]) {
        expect(
          FloorControl().classify(heard),
          FloorClaim.correction,
          reason: '"$heard" is a request to stop, however short.',
        );
      }
    });

    test('hears a real question as substance', () {
      for (final String heard in <String>[
        '你可以解釋',
        '為什麼',
        '那我想問',
        'can you explain',
        '介紹一下台北',
      ]) {
        expect(
          FloorControl().classify(heard),
          FloorClaim.substance,
          reason: '"$heard" is neither an acknowledgement nor a stop.',
        );
      }
    });

    test('reads through the punctuation the recogniser adds', () {
      expect(FloorControl().classify('OK。'), FloorClaim.backchannel);
      expect(FloorControl().classify('嗯，'), FloorClaim.backchannel);
      expect(FloorControl().classify('  好的！ '), FloorClaim.backchannel);
      expect(FloorControl().classify('不對！'), FloorClaim.correction);
    });

    test('an acknowledgement that grows into a question stops being one', () {
      // Partials arrive as the sentence is spoken, so the same utterance is
      // classified again at every character. "嗯" must not hold its verdict
      // once the words after it arrive.
      expect(FloorControl().classify('嗯'), FloorClaim.backchannel);
      expect(FloorControl().classify('嗯，那個'), FloorClaim.substance);
      expect(FloorControl().classify('嗯那我想問一下'), FloorClaim.substance);
    });

    test('nothing said claims nothing', () {
      expect(FloorControl().classify(''), FloorClaim.silence);
      expect(FloorControl().classify('   '), FloorClaim.silence);
      expect(FloorControl().classify('。、，'), FloorClaim.silence);
    });
  });

  group('FloorControl.takesTheFloor', () {
    test('anything said takes a floor nobody is holding', () {
      for (final String heard in <String>['嗯', 'OK', '不對', '為']) {
        expect(
          FloorControl().takesTheFloor(heard, agentIsSpeaking: false),
          isTrue,
          reason: 'With nothing being said there is nothing to take away.',
        );
      }
    });

    test('silence takes no floor at all', () {
      expect(FloorControl().takesTheFloor('', agentIsSpeaking: false), isFalse);
      expect(
        FloorControl().takesTheFloor('  ', agentIsSpeaking: true),
        isFalse,
      );
    });

    test('acknowledging a speaking agent does not stop it', () {
      for (final String heard in <String>['嗯嗯', 'OK', '對對對對對', '原來如此']) {
        expect(
          FloorControl().takesTheFloor(heard, agentIsSpeaking: true),
          isFalse,
          reason: '"$heard" means carry on, at any length.',
        );
      }
    });

    test('correcting a speaking agent stops it at once', () {
      for (final String heard in <String>['不對', '等等', '停']) {
        expect(
          FloorControl().takesTheFloor(heard, agentIsSpeaking: true),
          isTrue,
          reason: '"$heard" must land as fast as it is spoken.',
        );
      }
    });

    test('one stray syllable does not stop a speaking agent', () {
      // A single misheard character used to be enough. Substance has to
      // reach [FloorControl.charactersOfSubstance] before it interrupts.
      expect(FloorControl().takesTheFloor('計', agentIsSpeaking: true), isFalse);
      expect(
        FloorControl().takesTheFloor('計算', agentIsSpeaking: true),
        isFalse,
      );
      expect(
        FloorControl().takesTheFloor('計算機', agentIsSpeaking: true),
        isTrue,
      );
    });

    test('an English aside is measured in words, not characters', () {
      // Three Latin characters is most of one Chinese syllable's worth of
      // speech and nowhere near three of them. Counting runes charged
      // "the" as an interruption and "你可以解釋" as the same size.
      expect(
        FloorControl().takesTheFloor('the', agentIsSpeaking: true),
        isFalse,
      );
      expect(
        FloorControl().takesTheFloor('can you explain', agentIsSpeaking: true),
        isTrue,
      );
    });
  });
}

void _ownWordsGroup() {
  group("FloorControl with the user's own words", () {
    test('a sound the user makes while listening stops interrupting', () {
      // The built-in list is a guess at how people say "carry on". The user's
      // own is not a guess, and it is the one that has to win.
      final FloorControl mine = FloorControl(
        alsoAcknowledgements: <String>['蛤', '真的假的喔'],
      );

      expect(mine.classify('蛤'), FloorClaim.backchannel);
      expect(
        mine.classify('蛤蛤蛤'),
        FloorClaim.backchannel,
        reason: 'One character repeats, the same way 嗯嗯 does.',
      );
      expect(mine.classify('真的假的喔'), FloorClaim.backchannel);
      expect(
        mine.classify('真的假的喔我想問'),
        FloorClaim.substance,
        reason: 'A phrase is matched whole; anything after it is a question.',
      );
    });

    test('a way the user says stop takes the floor at once', () {
      final FloorControl mine = FloorControl(
        alsoCorrections: <String>['先停', 'hang on'],
      );

      expect(mine.classify('先停'), FloorClaim.correction);
      expect(
        mine.classify('先停一下我想想'),
        FloorClaim.correction,
        reason: 'A correction rarely arrives alone.',
      );
      expect(mine.classify('hang on'), FloorClaim.correction);
      expect(mine.classify('hang'), FloorClaim.correction);
      expect(
        mine.classify('hanging'),
        FloorClaim.substance,
        reason: 'Matched by word, so a longer word is a different word.',
      );
    });

    test('the built-in words are still there underneath', () {
      final FloorControl mine = FloorControl(
        alsoAcknowledgements: <String>['蛤'],
        alsoCorrections: <String>['先停'],
      );

      expect(mine.classify('嗯嗯'), FloorClaim.backchannel);
      expect(mine.classify('不對'), FloorClaim.correction);
      expect(mine.classify('你可以解釋'), FloorClaim.substance);
    });

    test('a word listed as both is a correction', () {
      // Corrections are checked first on purpose: being unable to stop the
      // agent is the worse of the two failures.
      final FloorControl mine = FloorControl(alsoCorrections: <String>['好']);

      expect(mine.classify('好'), FloorClaim.correction);
    });

    test('blank entries are ignored rather than matching everything', () {
      final FloorControl mine = FloorControl(
        alsoAcknowledgements: <String>['', '   '],
        alsoCorrections: <String>['', '  '],
      );

      expect(mine.classify('你可以解釋'), FloorClaim.substance);
      expect(mine.classify('嗯'), FloorClaim.backchannel);
    });

    test('the standard policy is what a profile that says nothing gets', () {
      expect(
        FloorControl().classify('嗯嗯'),
        FloorControl(alsoAcknowledgements: <String>[]).classify('嗯嗯'),
      );
    });
  });
}

void _spokenForGroup() {
  group('FloorControl with how long the speech ran', () {
    // The one signal that needs no words. Every lexicon above is an
    // assertion about one language; this is not, so it is what a language
    // nobody has written a list for falls back to.
    final FloorControl standard = FloorControl.standard;

    test('a brief noise does not take the floor however it transcribes', () {
      // 「うんうん」 is four syllables of Japanese agreement and would pass
      // the syllable floor. Half a second of speech is not a request to
      // stop in any language.
      expect(
        standard.takesTheFloor(
          'うんうん',
          agentIsSpeaking: true,
          spokenFor: const Duration(milliseconds: 300),
        ),
        isFalse,
      );
    });

    test('the same words said for longer do take it', () {
      expect(
        standard.takesTheFloor(
          'うんうん',
          agentIsSpeaking: true,
          spokenFor: const Duration(milliseconds: 900),
        ),
        isTrue,
      );
    });

    test('a correction lands however short it was', () {
      // 「不對」 is about 350ms. Being unable to stop the agent is the worse
      // failure, so a word that means stop outranks the clock.
      expect(
        standard.takesTheFloor(
          '不對',
          agentIsSpeaking: true,
          spokenFor: const Duration(milliseconds: 200),
        ),
        isTrue,
      );
    });

    test('an acknowledgement is ignored however long it was', () {
      expect(
        standard.takesTheFloor(
          '對對對對對',
          agentIsSpeaking: true,
          spokenFor: const Duration(seconds: 3),
        ),
        isFalse,
      );
    });

    test('an unmeasured burst behaves exactly as before', () {
      // Surfaces without a VAD behind them — tests, the preview — pass
      // nothing, and must not silently lose the ability to interrupt.
      expect(standard.takesTheFloor('你可以解釋', agentIsSpeaking: true), isTrue);
      expect(
        standard.takesTheFloor('你可以解釋', agentIsSpeaking: true, spokenFor: null),
        isTrue,
      );
    });

    test('the clock does not apply to a floor nobody is holding', () {
      expect(
        standard.takesTheFloor(
          'うん',
          agentIsSpeaking: false,
          spokenFor: const Duration(milliseconds: 100),
        ),
        isTrue,
      );
    });
  });
}
