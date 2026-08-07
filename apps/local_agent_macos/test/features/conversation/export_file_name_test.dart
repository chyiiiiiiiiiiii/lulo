import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/export_file_name.dart';

/// The title is the verbatim first thing the user said, so it can be anything.
void main() {
  test('an ordinary title is the file name', () {
    expect(exportFileName('明天台中天氣如何'), '明天台中天氣如何');
  });

  test('a title that starts with a dot does not become a hidden file', () {
    // Asking a local coding agent about `.zshrc` is an ordinary thing to do,
    // and it produced a file the Finder would not show.
    expect(exportFileName('.zshrc 怎麼設定'), 'zshrc 怎麼設定');
    expect(exportFileName('.'), 'conversation');
    expect(exportFileName('..'), 'conversation');
  });

  test('a dot inside a name is left alone', () {
    expect(exportFileName('Flutter 3.44.1 怎麼裝'), 'Flutter 3.44.1 怎麼裝');
  });

  test('characters the filesystem refuses are replaced', () {
    expect(exportFileName('a/b:c\\d'), 'a b c d');
  });

  test('nothing usable falls back to a name', () {
    expect(exportFileName(''), 'conversation');
    expect(exportFileName('   \n  '), 'conversation');
  });

  test('a long title is cut on whole characters', () {
    // Slicing UTF-16 code units can leave a lone surrogate, which the
    // platform channel replaces with U+FFFD.
    final String emoji = '${'a' * 59}🐈 and more';
    final String name = exportFileName(emoji);

    expect(name.runes.length, lessThanOrEqualTo(60));
    expect(name, isNot(contains('�')));
    expect(
      name.codeUnits.every((int unit) => unit < 0xD800 || unit > 0xDBFF)
          ? true
          : name.runes.last > 0xFFFF,
      isTrue,
      reason: 'the name ends on half a character',
    );
  });

  test('a long Han title still fits the byte limit', () {
    final String name = exportFileName('天' * 200);
    expect(name.runes.length, 60);
  });
}
