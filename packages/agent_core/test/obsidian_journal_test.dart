import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  test('a day is named in the order that sorts', () {
    expect(obsidianJournalFileName(DateTime(2026, 8, 5)), '2026-08-05.md');
  });

  test('the page opens with front matter Obsidian can search on', () {
    final String header = obsidianJournalHeader(
      DateTime(2026, 8, 28),
      heading: '與 Lulo 的對話',
    );
    expect(header, startsWith('---\n'));
    expect(header, contains('date: 2026-08-28'));
    expect(
      header,
      contains('source: lulo'),
      reason:
          'the user has to be able to find, or exclude, everything this '
          'app ever wrote in one query',
    );
    expect(header, contains('# 2026-08-28 與 Lulo 的對話'));
  });

  test('the question is the heading, and the answer follows it', () {
    final String entry = obsidianJournalEntry(
      at: DateTime(2026, 8, 28, 2, 4),
      question: '明天台中天氣如何',
      answer: '台中明天多雲，白天 28 度。',
    );
    expect(entry, contains('## 02:04 明天台中天氣如何'));
    expect(entry, contains('台中明天多雲，白天 28 度。'));
    expect(
      entry,
      isNot(contains('> 明天台中天氣如何')),
      reason: 'a question short enough to be a heading is not repeated',
    );
  });

  test('a question too long to be a heading is still kept whole', () {
    final String asked = '這是一個非常長的問題' * 12;
    final String entry = obsidianJournalEntry(
      at: DateTime(2026, 8, 28, 14, 30),
      question: asked,
      answer: '好的。',
    );
    expect(entry, contains('…'));
    expect(
      entry,
      contains('> $asked'),
      reason: 'the page has to be a better record than the app it outlives',
    );
  });

  test('a spoken question that ran over several lines is one heading', () {
    final String entry = obsidianJournalEntry(
      at: DateTime(2026, 8, 28, 9),
      question: '欸\n那個\n明天要幹嘛',
      answer: '不知道。',
    );
    expect(entry, contains('## 09:00 欸 那個 明天要幹嘛'));
    expect(
      entry.split('\n').where((String l) => l.startsWith('## ')),
      hasLength(1),
    );
  });

  test('cutting a long question does not cut a character in half', () {
    final String entry = obsidianJournalEntry(
      at: DateTime(2026, 8, 28, 9),
      question: '👨‍👩‍👧‍👦' * 40,
      answer: '好。',
    );
    expect(entry.contains('�'), isFalse);
  });

  test(
    'an entry begins with a blank line so it never joins what is above it',
    () {
      // It is appended to a file the user may have been writing in.
      final String entry = obsidianJournalEntry(
        at: DateTime(2026, 8, 28, 9),
        question: '嗨',
        answer: '嗨。',
      );
      expect(entry, startsWith('\n'));
      expect(entry, endsWith('\n'));
    },
  );
}
