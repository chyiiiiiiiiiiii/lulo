import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/widgets/completed_turn.dart';

Widget _host(String source) =>
    MaterialApp(home: Scaffold(body: TerminalMarkdown(source)));

/// Every visible string in the widget, joined.
String _visibleText(WidgetTester tester) {
  final Iterable<SelectableText> texts = tester.widgetList<SelectableText>(
    find.byType(SelectableText),
  );
  return texts
      .map(
        (SelectableText text) =>
            text.data ?? text.textSpan?.toPlainText() ?? '',
      )
      .join('\n');
}

void main() {
  testWidgets('a heading renders as its words, never as its syntax', (
    WidgetTester tester,
  ) async {
    // The model is told not to write Markdown and a 4B model sometimes does
    // anyway. The interface is the layer that can make that certain: what
    // an instruction cannot guarantee, the renderer absorbs — 「###」 on
    // screen is syntax shown to someone who never asked to read syntax.
    await tester.pumpWidget(_host('### 運動衝擊與關節壓力分析\n\n跑步是高衝擊運動。'));

    final String visible = _visibleText(tester);
    expect(visible, contains('運動衝擊與關節壓力分析'));
    expect(visible, isNot(contains('#')));
  });

  testWidgets('every heading depth sheds its marks', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host('# 一\n\n## 二\n\n###### 六'));
    final String visible = _visibleText(tester);
    expect(visible, contains('一'));
    expect(visible, contains('二'));
    expect(visible, contains('六'));
    expect(visible, isNot(contains('#')));
  });

  testWidgets('a hash inside a sentence is content, not a heading', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host('C# 和 F# 都是程式語言。'));
    expect(_visibleText(tester), contains('C# 和 F# 都是程式語言。'));
  });

  testWidgets('bold inside a heading still reads as words', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host('### 重點：**膝蓋**'));
    final String visible = _visibleText(tester);
    expect(visible, contains('重點：'));
    expect(visible, contains('膝蓋'));
    expect(visible, isNot(contains('*')));
  });
}
