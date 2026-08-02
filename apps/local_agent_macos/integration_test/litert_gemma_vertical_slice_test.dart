import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_agent_macos/app/app.dart';
import 'package:local_agent_macos/app/bootstrap.dart';

/// Absolute path to the installed Gemma 4 E4B model.
///
/// Supplied with `--dart-define=LOCAL_MODEL_PATH=...`. The test refuses to run
/// against a placeholder so a missing model can never look like a pass.
///
/// The path must be readable inside the app sandbox, so it has to live in the
/// application container rather than an arbitrary directory.
const String _modelPath = String.fromEnvironment('LOCAL_MODEL_PATH');

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real Gemma streams a turn, reuses the loaded model, then stops cleanly',
    (WidgetTester tester) async {
      expect(
        _modelPath,
        isNotEmpty,
        reason:
            'Pass --dart-define=LOCAL_MODEL_PATH to run the real-model slice.',
      );

      final Stopwatch sinceLaunch = Stopwatch()..start();
      final composition = createAppComposition(
        inferenceRuntime: 'litert',
        localModelPath: _modelPath,
      );
      await tester.pumpWidget(
        LocalAgentApp(
          composition: composition,
          presenceShaderLoader: _failShaderLoad,
        ),
      );
      await tester.pump();
      // The injected loader rejects on a microtask, so the setState that moves
      // the orb into its fallback lands after this first frame; the fallback
      // subtree only exists from the next one. Asserting on one pump was a
      // race that nothing noticed, because nothing ran this test.
      await tester.pump(const Duration(milliseconds: 32));

      expect(find.text('Start a conversation'), findsOneWidget);
      expect(find.byKey(const Key('agent-presence-fallback')), findsOneWidget);

      // Turn one pays the cold model load and must stream real tokens.
      await _submit(tester, 'Reply with one short sentence about local AI.');
      await _pumpUntil(
        tester,
        'the first real token',
        () => _streamingText(tester).isNotEmpty,
        timeout: const Duration(minutes: 8),
      );
      final int coldFirstTokenMillis = sinceLaunch.elapsedMilliseconds;
      expect(find.byKey(const Key('conversation-stop-button')), findsOneWidget);

      await _pumpUntil(
        tester,
        'the first turn to reach a terminal state',
        () => _terminalTexts(tester).isNotEmpty,
        timeout: const Duration(minutes: 8),
      );
      final String firstAnswer = _terminalTexts(tester).single;
      expect(
        firstAnswer.trim(),
        isNotEmpty,
        reason:
            'Gemma must produce real text, not an empty terminal turn. '
            'Visible screen text was: ${_visibleText(tester)}',
      );

      // Turn two reuses the loaded model, so it must not pay the load again.
      final Stopwatch warm = Stopwatch()..start();
      await _submit(tester, 'Say the single word: ready.');
      await _pumpUntil(
        tester,
        'the warm turn to produce output',
        () =>
            _streamingText(tester).isNotEmpty ||
            _terminalTexts(tester).length >= 2,
        timeout: const Duration(minutes: 4),
      );
      final int warmFirstTokenMillis = warm.elapsedMilliseconds;
      await _pumpUntil(
        tester,
        'the warm turn to reach a terminal state',
        () => _terminalTexts(tester).length >= 2,
        timeout: const Duration(minutes: 8),
      );
      expect(
        _terminalTexts(tester)[1].trim(),
        isNotEmpty,
        reason: 'The warm turn must also produce real text.',
      );
      expect(
        warmFirstTokenMillis,
        lessThan(coldFirstTokenMillis),
        reason: 'A warm turn must not pay the cold model-load cost again.',
      );

      // Turn three is stopped mid-stream and must not grow afterwards.
      await _submit(tester, 'Now count slowly from one to two hundred.');
      await _pumpUntil(
        tester,
        'the stopped turn to start streaming',
        () => _streamingText(tester).isNotEmpty,
        timeout: const Duration(minutes: 4),
      );
      final String beforeStop = _streamingText(tester);
      await tester.tap(find.byKey(const Key('conversation-stop-button')));
      await _pumpUntil(
        tester,
        'the stopped turn to settle',
        () => find.text('Response stopped').evaluate().isNotEmpty,
        timeout: const Duration(minutes: 2),
      );

      final String atStop = _terminalTexts(tester).last;
      // Give any late native delta a chance to (incorrectly) arrive.
      await _pumpFor(tester, const Duration(seconds: 3));
      expect(
        _terminalTexts(tester).last,
        atStop,
        reason: 'A cancelled turn must not grow after its terminal event.',
      );
      expect(atStop.length, greaterThanOrEqualTo(beforeStop.length));
      expect(
        find.byKey(const Key('conversation-submit-button')),
        findsOneWidget,
      );

      binding.reportData = <String, dynamic>{
        'litert_gemma_slice': <String, Object?>{
          'cold_first_token_millis': coldFirstTokenMillis,
          'warm_first_token_millis': warmFirstTokenMillis,
          'first_answer_characters': firstAnswer.trim().length,
          'terminal_turn_count': _terminalTexts(tester).length,
        },
      };

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

Future<void> _submit(WidgetTester tester, String prompt) async {
  await tester.enterText(
    find.byKey(const Key('conversation-composer-field')),
    prompt,
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('conversation-submit-button')));
  await tester.pump();
}

/// Pumps real frames until [condition] holds, then reports how long it took.
///
/// Streaming never goes idle, so `pumpAndSettle` cannot be used here.
Future<Duration> _pumpUntil(
  WidgetTester tester,
  String description,
  bool Function() condition, {
  required Duration timeout,
}) async {
  final Stopwatch elapsed = Stopwatch()..start();
  while (elapsed.elapsed < timeout) {
    if (condition()) {
      return elapsed.elapsed;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail(
    'Timed out after ${timeout.inSeconds}s waiting for $description. '
    'Terminal turns: ${_terminalTexts(tester).length}. '
    'Streaming: "${_streamingText(tester)}". '
    'Visible: ${_visibleText(tester)}',
  );
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final Stopwatch elapsed = Stopwatch()..start();
  while (elapsed.elapsed < duration) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The rendered text of one widget, covering both the plain and the rich
/// constructors.
///
/// Terminal Markdown paragraphs are built with `SelectableText.rich`, whose
/// `data` is null because the text lives in the span tree. Reading only `data`
/// silently reports an empty answer.
String? _widgetText(Widget widget) {
  if (widget is Text) {
    return widget.data ?? widget.textSpan?.toPlainText();
  }
  if (widget is SelectableText) {
    return widget.data ?? widget.textSpan?.toPlainText();
  }
  return null;
}

/// The streamed text of the active turn, or empty when no token has landed.
///
/// The widget renders a `Thinking…` placeholder before the first delta, so
/// that placeholder is deliberately reported as empty. Treating it as content
/// would let the test pass before Gemma produced anything.
String _streamingText(WidgetTester tester) {
  final Finder finder = find.byKey(const Key('active-streaming-plain-text'));
  if (finder.evaluate().isEmpty) {
    return '';
  }
  final String text = tester.widget<SelectableText>(finder).data ?? '';
  return text == 'Thinking…' ? '' : text;
}

/// Every string currently rendered, so a failure reports what the user saw
/// instead of only that an expectation was empty.
String _visibleText(WidgetTester tester) {
  final List<String> parts = <String>[];
  for (final Element element in find.byWidgetPredicate((Widget widget) {
    return _widgetText(widget) != null;
  }).evaluate()) {
    final String text = _widgetText(element.widget) ?? '';
    if (text.isNotEmpty) {
      parts.add(text);
    }
  }
  return parts.join(' | ');
}

/// Flattens each terminal turn, which renders as a column of rich blocks
/// rather than a single text widget.
List<String> _terminalTexts(WidgetTester tester) {
  final List<String> texts = <String>[];
  for (final Element root
      in find.byKey(const Key('terminal-markdown')).evaluate()) {
    final StringBuffer buffer = StringBuffer();
    void visit(Element element) {
      final String? text = _widgetText(element.widget);
      if (text != null) {
        buffer.write(text);
        return;
      }
      element.visitChildren(visit);
    }

    root.visitChildren(visit);
    texts.add(buffer.toString());
  }
  return texts;
}

Future<ui.FragmentProgram> _failShaderLoad() async {
  throw UnsupportedError('Runtime shader rendering is outside this test.');
}
