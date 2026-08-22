import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/widgets/completed_turn.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

/// What the user can do with a turn once it has been said.
///
/// A local model gets an answer wrong often enough that reading it is not the
/// only thing anyone wants to do with one, and until now reading it was all
/// the conversation offered.
void main() {
  const Turn answer = Turn(
    role: TurnRole.assistant,
    text: '好，我幫你查一下。',
    status: TurnStatus.completed,
  );

  Future<List<MethodCall>> pumpTurn(WidgetTester tester, Turn turn) async {
    final List<MethodCall> platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: CompletedTurn(turn: turn)),
      ),
    );
    return platformCalls;
  }

  testWidgets('an answer can be read aloud on demand', (
    WidgetTester tester,
  ) async {
    // Typed answers are not spoken by default — the mode of the answer
    // follows the mode of the ask — but hearing one should never require
    // turning the microphone on and asking again.
    final List<String> spoken = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CompletedTurn(turn: answer, onSpeak: spoken.add),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('turn-speak')));
    expect(spoken, <String>['好，我幫你查一下。']);
  });

  testWidgets('nothing to speak with means no speak button', (
    WidgetTester tester,
  ) async {
    await pumpTurn(tester, answer);
    expect(find.byKey(const Key('turn-speak')), findsNothing);
  });

  testWidgets('a question of the user\'s is never read back to them', (
    WidgetTester tester,
  ) async {
    // Reading the user their own words is the one thing the button must
    // not offer: they wrote it.
    const Turn question = Turn(
      role: TurnRole.user,
      text: '幫我查一下',
      status: TurnStatus.completed,
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CompletedTurn(turn: question, onSpeak: (String _) {}),
        ),
      ),
    );
    expect(find.byKey(const Key('turn-speak')), findsNothing);
  });

  testWidgets('an answer can be taken away as text', (
    WidgetTester tester,
  ) async {
    final List<MethodCall> platformCalls = await pumpTurn(tester, answer);

    await tester.tap(find.byKey(const Key('turn-copy-button')));
    await tester.pump();

    final MethodCall copy = platformCalls.singleWhere(
      (MethodCall call) => call.method == 'Clipboard.setData',
    );
    expect(
      (copy.arguments as Map<Object?, Object?>)['text'],
      '好，我幫你查一下。',
      reason: 'the clipboard did not get the turn the user copied',
    );
  });

  testWidgets('copying says so, and stops saying so', (
    WidgetTester tester,
  ) async {
    await pumpTurn(tester, answer);

    expect(find.byKey(const Key('turn-copied')), findsNothing);
    await tester.tap(find.byKey(const Key('turn-copy-button')));
    await tester.pump();

    // Without this the only evidence the click did anything is a clipboard
    // the user has to go and check somewhere else.
    expect(find.byKey(const Key('turn-copied')), findsOneWidget);

    await tester.pump(CompletedTurn.copiedNoticeDuration);
    await tester.pump();
    expect(
      find.byKey(const Key('turn-copied')),
      findsNothing,
      reason: 'the notice stayed on a turn the user has moved on from',
    );
  });

  testWidgets('what the user said can be copied too', (
    WidgetTester tester,
  ) async {
    final List<MethodCall> platformCalls = await pumpTurn(
      tester,
      const Turn(
        role: TurnRole.user,
        text: '幫我看一下明天的行程',
        status: TurnStatus.completed,
      ),
    );

    await tester.tap(find.byKey(const Key('turn-copy-button')));
    await tester.pump();

    final MethodCall copy = platformCalls.singleWhere(
      (MethodCall call) => call.method == 'Clipboard.setData',
    );
    expect((copy.arguments as Map<Object?, Object?>)['text'], '幫我看一下明天的行程');
  });

  testWidgets('the last answer can be asked for again', (
    WidgetTester tester,
  ) async {
    int asked = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CompletedTurn(turn: answer, onRegenerate: () => asked++),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('turn-regenerate-button')));
    await tester.pump();

    expect(asked, 1);
  });

  testWidgets('a turn nothing can be retried on offers no retry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: CompletedTurn(turn: answer)),
      ),
    );

    expect(find.byKey(const Key('turn-regenerate-button')), findsNothing);
    expect(find.byKey(const Key('turn-revise-button')), findsNothing);
    expect(
      find.byKey(const Key('turn-copy-button')),
      findsOneWidget,
      reason: 'copying is always available; retrying is not',
    );
  });

  testWidgets('a question can be rewritten in place and asked again', (
    WidgetTester tester,
  ) async {
    const Turn question = Turn(
      role: TurnRole.user,
      text: '明天天氣如何',
      status: TurnStatus.completed,
    );
    final List<String> revisions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CompletedTurn(turn: question, onRevise: revisions.add),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('turn-revise-button')));
    await tester.pump();

    // The question it opens on is the question that was asked, so a small
    // repair is a small edit rather than typing the whole thing again.
    final Finder field = find.byKey(const Key('turn-revise-field'));
    expect(tester.widget<TextField>(field).controller?.text, '明天天氣如何');

    await tester.enterText(field, '後天天氣如何');
    await tester.tap(find.byKey(const Key('turn-revise-submit')));
    await tester.pump();

    expect(revisions, <String>['後天天氣如何']);
  });

  testWidgets('backing out of a rewrite leaves the question alone', (
    WidgetTester tester,
  ) async {
    const Turn question = Turn(
      role: TurnRole.user,
      text: '明天天氣如何',
      status: TurnStatus.completed,
    );
    final List<String> revisions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CompletedTurn(turn: question, onRevise: revisions.add),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('turn-revise-button')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('turn-revise-field')),
      '完全不同的問題',
    );
    await tester.tap(find.byKey(const Key('turn-revise-cancel')));
    await tester.pump();

    expect(revisions, isEmpty);
    expect(find.byKey(const Key('turn-revise-field')), findsNothing);
    expect(find.text('明天天氣如何'), findsOneWidget);
  });

  testWidgets('a turn bubble is glass over the window, not paint', (
    WidgetTester tester,
  ) async {
    // The window behind the conversation blurs the desktop through it, and a
    // bubble wide enough to fill the window painted that glass back out over
    // most of the surface. Behind a bubble the desktop should still be there
    // — dimmer, not gone.
    Color bubbleColorAround(Finder content) {
      final Iterable<Container> containers = tester.widgetList<Container>(
        find.ancestor(of: content, matching: find.byType(Container)),
      );
      final BoxDecoration decoration = containers
          .map((Container container) => container.decoration)
          .whereType<BoxDecoration>()
          .first;
      return decoration.color!;
    }

    await pumpTurn(tester, answer);
    expect(bubbleColorAround(find.byType(TerminalMarkdown)).a, lessThan(1.0));

    const Turn question = Turn(
      role: TurnRole.user,
      text: '明天天氣如何',
      status: TurnStatus.completed,
    );
    await pumpTurn(tester, question);
    expect(bubbleColorAround(find.text('明天天氣如何')).a, lessThan(1.0));
  });

  testWidgets('an unchanged turn reuses its Markdown instead of reparsing', (
    WidgetTester tester,
  ) async {
    // The transcript is a plain Column, so every ancestor rebuild re-runs
    // every turn's build. With the Markdown re-parsed and its
    // SelectableTexts re-created each time, opening the window stalled the
    // UI thread for 90-176ms on a long conversation — measured by
    // TransitionFrameProbe. An identical widget instance is Flutter's own
    // short-circuit: the element sees the same object and skips the whole
    // subtree.
    final GlobalKey<_RebuilderState> rebuilder = GlobalKey<_RebuilderState>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: _Rebuilder(
            key: rebuilder,
            // Built the way the transcript builds it: a fresh instance with
            // fresh closures on every ancestor rebuild, never const.
            child: () => CompletedTurn(turn: answer, onSpeak: (String _) {}),
          ),
        ),
      ),
    );
    final TerminalMarkdown before = tester.widget<TerminalMarkdown>(
      find.byType(TerminalMarkdown),
    );

    rebuilder.currentState!.rebuild();
    await tester.pump();

    final TerminalMarkdown after = tester.widget<TerminalMarkdown>(
      find.byType(TerminalMarkdown),
    );
    expect(
      identical(before, after),
      isTrue,
      reason: 'A rebuild with the same text must not rebuild the Markdown.',
    );
  });
}

/// Rebuilds its child factory on demand, the way any ancestor setState does.
final class _Rebuilder extends StatefulWidget {
  const _Rebuilder({required this.child, super.key});
  final Widget Function() child;
  @override
  State<_Rebuilder> createState() => _RebuilderState();
}

final class _RebuilderState extends State<_Rebuilder> {
  /// Forces a fresh build, recreating the child widget instance.
  void rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) => widget.child();
}
