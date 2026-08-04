import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
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
          FloorControl.classify(heard),
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
          FloorControl.classify(heard),
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
          FloorControl.classify(heard),
          FloorClaim.substance,
          reason: '"$heard" is neither an acknowledgement nor a stop.',
        );
      }
    });

    test('reads through the punctuation the recogniser adds', () {
      expect(FloorControl.classify('OK。'), FloorClaim.backchannel);
      expect(FloorControl.classify('嗯，'), FloorClaim.backchannel);
      expect(FloorControl.classify('  好的！ '), FloorClaim.backchannel);
      expect(FloorControl.classify('不對！'), FloorClaim.correction);
    });

    test('an acknowledgement that grows into a question stops being one', () {
      // Partials arrive as the sentence is spoken, so the same utterance is
      // classified again at every character. "嗯" must not hold its verdict
      // once the words after it arrive.
      expect(FloorControl.classify('嗯'), FloorClaim.backchannel);
      expect(FloorControl.classify('嗯，那個'), FloorClaim.substance);
      expect(FloorControl.classify('嗯那我想問一下'), FloorClaim.substance);
    });

    test('nothing said claims nothing', () {
      expect(FloorControl.classify(''), FloorClaim.silence);
      expect(FloorControl.classify('   '), FloorClaim.silence);
      expect(FloorControl.classify('。、，'), FloorClaim.silence);
    });
  });

  group('FloorControl.takesTheFloor', () {
    test('anything said takes a floor nobody is holding', () {
      for (final String heard in <String>['嗯', 'OK', '不對', '為']) {
        expect(
          FloorControl.takesTheFloor(heard, agentIsSpeaking: false),
          isTrue,
          reason: 'With nothing being said there is nothing to take away.',
        );
      }
    });

    test('silence takes no floor at all', () {
      expect(FloorControl.takesTheFloor('', agentIsSpeaking: false), isFalse);
      expect(FloorControl.takesTheFloor('  ', agentIsSpeaking: true), isFalse);
    });

    test('acknowledging a speaking agent does not stop it', () {
      for (final String heard in <String>['嗯嗯', 'OK', '對對對對對', '原來如此']) {
        expect(
          FloorControl.takesTheFloor(heard, agentIsSpeaking: true),
          isFalse,
          reason: '"$heard" means carry on, at any length.',
        );
      }
    });

    test('correcting a speaking agent stops it at once', () {
      for (final String heard in <String>['不對', '等等', '停']) {
        expect(
          FloorControl.takesTheFloor(heard, agentIsSpeaking: true),
          isTrue,
          reason: '"$heard" must land as fast as it is spoken.',
        );
      }
    });

    test('one stray syllable does not stop a speaking agent', () {
      // A single misheard character used to be enough. Substance has to
      // reach [FloorControl.charactersOfSubstance] before it interrupts.
      expect(FloorControl.takesTheFloor('計', agentIsSpeaking: true), isFalse);
      expect(FloorControl.takesTheFloor('計算', agentIsSpeaking: true), isFalse);
      expect(FloorControl.takesTheFloor('計算機', agentIsSpeaking: true), isTrue);
    });

    test('an English aside is measured in words, not characters', () {
      // Three Latin characters is most of one Chinese syllable's worth of
      // speech and nowhere near three of them. Counting runes charged
      // "the" as an interruption and "你可以解釋" as the same size.
      expect(FloorControl.takesTheFloor('the', agentIsSpeaking: true), isFalse);
      expect(
        FloorControl.takesTheFloor('can you explain', agentIsSpeaking: true),
        isTrue,
      );
    });
  });
}
