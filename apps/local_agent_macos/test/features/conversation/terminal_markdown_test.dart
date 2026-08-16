import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/widgets/completed_turn.dart';

Widget _host(String source) =>
    MaterialApp(home: Scaffold(body: TerminalMarkdown(source)));

/// How many rendered list items the tree holds.
int _listItems(WidgetTester tester) => tester
    .widgetList(find.byType(Padding))
    .where(
      (Widget widget) => widget.key.toString().contains('markdown-list-item'),
    )
    .length;

/// Every visible string in the widget, joined — selectable text and the
/// plain [Text] the list gutter uses for its markers.
String _visibleText(WidgetTester tester) {
  final Iterable<String> selectable = tester
      .widgetList<SelectableText>(find.byType(SelectableText))
      .map(
        (SelectableText text) =>
            text.data ?? text.textSpan?.toPlainText() ?? '',
      );
  final Iterable<String> plain = tester
      .widgetList<Text>(find.byType(Text))
      .map((Text text) => text.data ?? text.textSpan?.toPlainText() ?? '');
  return <String>[...selectable, ...plain].join('\n');
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

  testWidgets('list items shed their dashes and stand apart', (
    WidgetTester tester,
  ) async {
    // The reader's list, not the writer's: each item gets a bullet gutter
    // and a hanging indent, so a wrapped line aligns under its own text
    // instead of crashing into the margin — the shape every reading app
    // converged on.
    await tester.pumpWidget(_host('優點：\n\n- 提升力量與表現\n- 肌肉量增加\n- 提升恢復力'));
    final String visible = _visibleText(tester);
    expect(visible, contains('提升力量與表現'));
    expect(visible, contains('肌肉量增加'));
    expect(
      visible,
      isNot(contains('- 提升')),
      reason: 'the dash is layout, not content',
    );
    expect(_listItems(tester), 3);
  });

  testWidgets('numbered items keep their numbers in the gutter', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host('步驟：\n\n1. 先暖身\n2. 再拉伸'));
    final String visible = _visibleText(tester);
    expect(visible, contains('先暖身'));
    expect(visible, contains('1.'));
    expect(_listItems(tester), 2);
  });

  testWidgets('a dash mid-sentence stays a dash', (WidgetTester tester) async {
    await tester.pumpWidget(_host('溫度大約是 -5 度。'));
    expect(_visibleText(tester), contains('-5 度'));
    expect(_listItems(tester), 0);
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
