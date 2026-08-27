import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/widgets/completed_turn.dart';
import 'package:local_agent_macos/features/conversation/widgets/streaming_markdown.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('the settled paragraphs are built once, not once per token', (
    tester,
  ) async {
    int settledBuilds = 0;
    String source = '第一段已經寫完了。\n\n第二段也寫完了。\n\n第三段正在';
    late StateSetter setSource;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            setSource = setState;
            return StreamingMarkdown(
              source,
              onSettledBuild: () => settledBuilds += 1,
            );
          },
        ),
      ),
    );
    final int afterFirst = settledBuilds;
    expect(afterFirst, greaterThan(0));

    for (final String more in <String>['寫', '到', '一', '半']) {
      setSource(() => source = '$source$more');
      await tester.pump();
    }

    expect(
      settledBuilds,
      afterFirst,
      reason: 'growing the tail must not rebuild what has already settled',
    );
  });

  testWidgets('a new paragraph settles the one before it', (tester) async {
    int settledBuilds = 0;
    String source = '第一段。\n\n第二段正在寫';
    late StateSetter setSource;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            setSource = setState;
            return StreamingMarkdown(
              source,
              onSettledBuild: () => settledBuilds += 1,
            );
          },
        ),
      ),
    );
    final int afterFirst = settledBuilds;

    setSource(() => source = '$source。\n\n第三段開始');
    await tester.pump();

    expect(settledBuilds, afterFirst + 1);
  });

  testWidgets('shows the same words the finished renderer shows', (
    tester,
  ) async {
    const String source =
        '開頭這一段有 **重點**。\n\n'
        '## 一個標題\n\n'
        '- 第一點\n- 第二點\n\n'
        '```dart\nfinal int x = 1;\n```\n\n'
        '收尾這一段。';
    await tester.pumpWidget(host(const TerminalMarkdown(source)));
    final List<String> finished = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map(_readableOf)
        .toList();

    await tester.pumpWidget(host(const StreamingMarkdown(source)));
    final List<String> streaming = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map(_readableOf)
        .toList();

    expect(streaming, finished);
  });

  testWidgets('an unterminated code fence settles the same as it finishes', (
    tester,
  ) async {
    // The blank line inside the fence is the last one in the source. Settling
    // there would cut the block in two and render half of it as prose, so
    // the streamed shape has to stay what the finished renderer shows.
    const String source = '前言。\n\n```dart\nfinal a = 1;\n\nfinal b = 2;\n';
    await tester.pumpWidget(host(const TerminalMarkdown(source)));
    final List<String> finished = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map(_readableOf)
        .toList();

    await tester.pumpWidget(host(const StreamingMarkdown(source)));

    expect(
      tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map(_readableOf)
          .toList(),
      finished,
    );
  });
}

String _readableOf(SelectableText text) =>
    text.data ?? text.textSpan?.toPlainText() ?? '';
