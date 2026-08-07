import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/conversation_repository.dart';
import 'package:local_agent_macos/features/conversation/conversation_view.dart';
import 'package:local_agent_macos/features/conversation/conversation_view_model.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

import '../../support/controlled_inference_service.dart';
import '../../support/recording_conversation_storage_service.dart';

void main() {
  testWidgets('empty conversation presents a focused composer', (tester) async {
    final _Harness harness = _Harness();
    await tester.pumpWidget(harness.app());

    expect(find.text('Start a conversation'), findsOneWidget);
    expect(
      find.byKey(const Key('conversation-composer-field')),
      findsOneWidget,
    );
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'Conversation composer',
    );

    await _finish(tester);
  });

  testWidgets('submit sends trimmed text and restores an empty composer', (
    tester,
  ) async {
    final _Harness harness = _Harness();
    await tester.pumpWidget(harness.app());

    await tester.enterText(
      find.byKey(const Key('conversation-composer-field')),
      '  Hello Gemma  ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('conversation-submit-button')));
    await tester.pump();
    await harness.inference.requestReceived;

    expect(harness.inference.requests.single.prompt, 'Hello Gemma');
    expect(find.text('Hello Gemma'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('conversation-composer-field')),
          )
          .controller
          ?.text,
      isEmpty,
    );

    harness.start(prompt: 'Hello Gemma');
    harness.complete();
    await tester.pump();
    await _finish(tester);
  });

  testWidgets('enter submits while shift-enter inserts a newline', (
    tester,
  ) async {
    final _Harness harness = _Harness();
    await tester.pumpWidget(harness.app());
    final Finder field = find.byKey(const Key('conversation-composer-field'));

    await tester.enterText(field, 'Line one');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller?.text, 'Line one\n');

    await tester.enterText(field, 'Keyboard prompt');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await harness.inference.requestReceived;
    expect(harness.inference.requests.single.prompt, 'Keyboard prompt');

    harness.start(prompt: 'Keyboard prompt');
    harness.complete();
    await tester.pump();
    await _finish(tester);
  });

  testWidgets('active generation exposes stop and delegates cancellation', (
    tester,
  ) async {
    final _Harness harness = _Harness();
    await tester.pumpWidget(harness.app());
    await _submit(tester, 'Hello');
    await harness.inference.requestReceived;
    harness.start();
    harness.inference.emit(
      const GenerationDelta(
        generationId: GenerationId('generation-1'),
        delta: 'Partial response',
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('conversation-stop-button')), findsOneWidget);
    await tester.runAsync(harness.viewModel.stop);
    await tester.pump();

    expect(harness.inference.cancellations, const <GenerationId>[
      GenerationId('generation-1'),
    ]);
    expect(find.text('Partial response'), findsOneWidget);
    expect(find.text('Response stopped'), findsOneWidget);
    expect(find.byKey(const Key('conversation-submit-button')), findsOneWidget);

    await _finish(tester);
  });

  testWidgets('failed turn has visible status semantics', (tester) async {
    final _Harness harness = _Harness();
    await tester.pumpWidget(harness.app());
    await _submit(tester, 'Hello');
    await harness.inference.requestReceived;
    harness.start();
    harness.inference.emit(
      const GenerationDelta(
        generationId: GenerationId('generation-1'),
        delta: 'Partial',
      ),
    );
    harness.inference.emit(
      const GenerationFailed(
        generationId: GenerationId('generation-1'),
        failure: ConversationFailure('runtime failed'),
      ),
    );
    await tester.pump();

    expect(find.text('Response failed'), findsOneWidget);

    await _finish(tester);
  });

  testWidgets('streaming and completed output share one Markdown layout', (
    tester,
  ) async {
    // The stream once showed raw text — paragraph breaks as full blank
    // lines — and the bubble visibly shrank when completion swapped in
    // the block renderer with its tighter spacing. One renderer for
    // both is what makes the hand-off invisible.
    final _Harness harness = _Harness();
    await tester.pumpWidget(harness.app());
    await _submit(tester, 'Format this');
    await harness.inference.requestReceived;
    harness.start(prompt: 'Format this');
    harness.inference.emit(
      const GenerationDelta(
        generationId: GenerationId('generation-1'),
        delta: '**Bold**\n\n```dart\nvoid main() {}\n```',
      ),
    );
    // The token batcher hands text over on a timer, not a microtask.
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('active-streaming-markdown')), findsOneWidget);
    expect(find.text('Bold'), findsOneWidget);
    expect(find.text('void main() {}'), findsOneWidget);

    harness.complete();
    await tester.pump();

    expect(find.byKey(const Key('active-streaming-markdown')), findsNothing);
    expect(find.byKey(const Key('terminal-markdown')), findsOneWidget);
    expect(find.text('Bold'), findsOneWidget);
    expect(find.text('void main() {}'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('removing the view disposes its active operation', (
    tester,
  ) async {
    final _Harness harness = _Harness();
    await tester.pumpWidget(harness.app());
    await _submit(tester, 'Hello');
    await harness.inference.requestReceived;
    harness.start();
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(harness.inference.cancellations, const <GenerationId>[
      GenerationId('generation-1'),
    ]);

    // The view already owns and disposed the operation subscription.
  });
}

Future<void> _submit(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const Key('conversation-composer-field')),
    text,
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('conversation-submit-button')));
  await tester.pump();
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

final class _Harness {
  final RecordingConversationStorageService storage =
      RecordingConversationStorageService();
  final ControlledInferenceService inference = ControlledInferenceService();
  late final ConversationRepository repository = ConversationRepository(
    storageService: storage,
    inferenceService: inference,
  );
  late final ConversationViewModel viewModel = ConversationViewModel(
    repository: repository,
    idFactory: () => const ConversationId('conversation-1'),
  );

  ConversationViewModel createViewModel() => viewModel;

  Widget app() => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ConversationView(viewModelFactory: createViewModel),
  );

  void start({String prompt = 'Hello'}) {
    inference.emit(
      GenerationStarted(
        Generation(
          id: const GenerationId('generation-1'),
          request: GenerationRequest(
            conversationId: const ConversationId('conversation-1'),
            prompt: prompt,
          ),
        ),
      ),
    );
  }

  void complete() {
    inference.emit(const GenerationCompleted(GenerationId('generation-1')));
  }
}
