import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

/// A fully local app with no cloud backup has one way out of it, and this is
/// it. The renderer is pure so that what leaves the machine is decided by
/// something that can be read in a test rather than by a widget.
void main() {
  Turn user(String text) =>
      Turn(role: TurnRole.user, text: text, status: TurnStatus.completed);
  Turn assistant(String text, [TurnStatus status = TurnStatus.completed]) =>
      Turn(role: TurnRole.assistant, text: text, status: status);

  const ConversationLabels labels = ConversationLabels(
    user: 'You',
    assistant: 'Lulo',
    interrupted: 'interrupted',
    stopped: 'stopped',
    failed: 'failed',
    doubted: 'heard with low confidence',
  );

  test('a conversation reads as a conversation', () {
    final String out = conversationToMarkdown(
      title: 'Weather',
      turns: <Turn>[user('明天天氣如何'), assistant('明天多雲。')],
      labels: labels,
    );

    expect(out, '''
# Weather

**You**

明天天氣如何

**Lulo**

明天多雲。
''');
  });

  test('a turn that did not finish says so', () {
    // The record has to be honest about what happened, or an export becomes
    // a nicer version of the conversation than the one the user had.
    final String out = conversationToMarkdown(
      title: 'Weather',
      turns: <Turn>[user('明天天氣如何'), assistant('明天多', TurnStatus.interrupted)],
      labels: labels,
    );

    expect(out, contains('**Lulo** *(interrupted)*'));
  });

  test('a heading in an answer cannot forge a turn', () {
    // Answers are Markdown already. Without escaping, a model that writes
    // "**You**" produces an export where it looks like the user said it.
    final String out = conversationToMarkdown(
      title: 'x',
      turns: <Turn>[assistant('**You**\n\nI never said this.')],
      labels: labels,
    );

    expect(
      '\n$out'.split('\n**You**\n').length,
      1,
      reason: 'an answer forged a turn boundary',
    );
  });

  test('an empty conversation is still a valid document', () {
    expect(
      conversationToMarkdown(title: 'Nothing', turns: <Turn>[], labels: labels),
      '# Nothing\n',
    );
  });

  test('a title with Markdown in it does not break the heading', () {
    final String out = conversationToMarkdown(
      title: '# not a heading\nsecond line',
      turns: <Turn>[],
      labels: labels,
    );

    expect(
      out.split('\n').where((String l) => l.startsWith('#')),
      hasLength(1),
    );
  });

  group('an answer cannot corrupt the document around it', () {
    // This file is the user's only copy. An answer that renders as something
    // other than what was said is data loss, and every case below is an
    // ordinary thing for a model to write.
    String render(String answer) => conversationToMarkdown(
      title: 'x',
      turns: <Turn>[assistant(answer), user('後來呢')],
      labels: labels,
    );

    test('an indented forgery is caught too', () {
      // CommonMark treats up to three leading spaces as an ordinary
      // paragraph, so "  **You**" is visually a turn boundary. Anchoring the
      // escape at column zero let a single space defeat it.
      final String out = render('  **You**\n\nI never said this.');
      expect(
        RegExp(r'^\s*\*\*You\*\*$', multiLine: true).allMatches(out).length,
        1,
        reason: 'an indented line forged a turn boundary',
      );
    });

    test('an unclosed code fence cannot swallow the rest', () {
      // Routine for an answer that was interrupted mid-stream, which this
      // renderer deliberately exports.
      final String out = render('```dart\nvoid main() {');
      expect(
        '\n\$out'.split(RegExp(r'\n```')).length.isOdd,
        isTrue,
        reason: 'the document ends inside a code fence',
      );
      expect(out, contains('後來呢'));
    });

    test('an unclosed HTML comment cannot hide the rest', () {
      final String out = render('<!-- thinking');
      expect(out, isNot(contains('<!--')));
      expect(out, contains('後來呢'));
    });

    test('what was said is still readable afterwards', () {
      // Escaping that mangles ordinary text would be its own kind of loss.
      expect(render('明天多雲。'), contains('明天多雲。'));
      expect(
        render('```dart\nvoid main() {}\n```'),
        contains('void main() {}'),
      );
    });
  });

  test('a doubted transcript stays doubted in the file', () {
    // The screen captions a turn the recogniser was unsure of rather than
    // showing it as certain. An export that dropped the caveat would present
    // a guess as a quotation.
    final TranscriptRefinement heard = TranscriptRefinement(
      rawTranscript: '幫我看 Flutter 的版本',
      proposedTranscript: null,
      selectedTranscript: '幫我看 Flutter 的版本',
      status: TranscriptRefinementStatus.rejected,
      edits: const <TranscriptEdit>[],
      rejectionReasons: const <TranscriptRejectionReason>[],
      refinerId: 'test',
      refinerVersion: '1',
      elapsed: Duration.zero,
      heardConfidence: 0.4,
    );
    final String out = conversationToMarkdown(
      title: 'x',
      turns: <Turn>[Turn.voice(voiceInput: heard)],
      labels: labels,
    );

    expect(out, contains('0.40'));
  });
}
