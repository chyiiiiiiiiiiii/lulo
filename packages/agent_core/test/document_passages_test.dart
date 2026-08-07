import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  const String lease = '''
第三條 租賃期間
本租約自民國一一五年三月一日起至一一六年二月二十八日止，為期一年。

第七條 修繕責任
房屋因自然損壞而需修繕時，由出租人負責。承租人使用不當造成之損壞，由承租人負責。

第九條 保固
出租人對房屋結構提供五年保固，自交屋日起算。
''';

  group('finding the part of a document a question is about', () {
    test('brings back the passage that answers it', () {
      // 40 pages do not fit in a 4096-token window, and the user should not
      // have to find the answer themselves in order to ask about it.
      final DocumentPassages found = passagesFor(
        question: '他們保固幾年',
        document: lease,
        maxCharacters: 400,
      );

      expect(found.passages, isNotEmpty);
      expect(found.passages.first, contains('五年保固'));
    });

    test('a question about nothing in the document brings back nothing', () {
      // Silence beats a passage chosen because it was first. An answer built
      // on an irrelevant passage is worse than one that says it does not
      // know, in an app whose core instruction is 不捏造資訊.
      final DocumentPassages found = passagesFor(
        question: '今天台北的天氣如何',
        document: lease,
        maxCharacters: 400,
      );

      expect(found.passages, isEmpty);
    });

    test('Chinese matches without word breaks', () {
      // The same asymmetry `searchConversations` documents: Han has no
      // spaces, so a matcher that needed them would never fire in the
      // language this app is mostly used in.
      final DocumentPassages found = passagesFor(
        question: '修繕誰負責',
        document: lease,
        maxCharacters: 400,
      );

      expect(found.passages.first, contains('修繕'));
    });

    test('what comes back fits the budget it was given', () {
      // The turn instruction shares a 4096-token window with the answer, so
      // a passage that does not fit is not a passage — it is an overflow,
      // and `LiteRTLMRuntimeBackend` fails those as an empty answer rather
      // than degrading.
      final DocumentPassages found = passagesFor(
        question: '保固 修繕 租賃',
        document: lease,
        maxCharacters: 120,
      );

      expect(
        found.passages.join().length,
        lessThanOrEqualTo(120),
        reason: 'the budget is a ceiling, not a suggestion',
      );
    });

    test('it says which part it used', () {
      // The user has to be able to check the answer against the document.
      // Without this the app is asserting something about a file the user
      // can read for themselves.
      final DocumentPassages found = passagesFor(
        question: '保固幾年',
        document: lease,
        maxCharacters: 400,
      );

      expect(found.usedCharacters, greaterThan(0));
      expect(found.usedCharacters, found.passages.join('\n\n').length);
    });

    test('an empty document and an empty question are both nothing', () {
      expect(
        passagesFor(question: '保固', document: '', maxCharacters: 400).passages,
        isEmpty,
      );
      expect(
        passagesFor(
          question: '   ',
          document: lease,
          maxCharacters: 400,
        ).passages,
        isEmpty,
      );
    });

    test('an English question finds an English passage', () {
      const String manual = '''
Warranty
The device is covered for two years from the date of purchase.

Cleaning
Wipe the housing with a dry cloth. Do not use solvents.
''';

      final DocumentPassages found = passagesFor(
        question: 'how long is the warranty',
        document: manual,
        maxCharacters: 400,
      );

      expect(found.passages.first, contains('two years'));
    });

    test('a common word alone does not drag in the whole document', () {
      // Matching on 「的」 or "the" would make every passage relevant, which
      // is the same as none being relevant and costs the whole budget.
      final DocumentPassages found = passagesFor(
        question: '的',
        document: lease,
        maxCharacters: 400,
      );

      expect(found.passages, isEmpty);
    });
  });
}
