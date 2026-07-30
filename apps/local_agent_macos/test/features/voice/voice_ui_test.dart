import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/conversation/conversation_repository.dart';
import 'package:local_agent_macos/features/conversation/conversation_view.dart';
import 'package:local_agent_macos/features/conversation/conversation_view_model.dart';
import 'package:local_agent_macos/features/voice/voice_service.dart';

import '../../support/controlled_inference_service.dart';
import '../../support/fake_voice_service.dart';
import '../../support/microtask_batch_scheduler.dart';

void main() {
  ConversationViewModel viewModel() => ConversationViewModel(
    repository: ConversationRepository(
      storageService: InMemoryConversationStorageService(),
      inferenceService: ControlledInferenceService(),
    ),
    idFactory: () => const ConversationId('conversation-1'),
    startFresh: true,
    batchScheduler: MicrotaskBatchScheduler(),
  );

  testWidgets('no voice behind the view means no microphone on it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ConversationView(viewModelFactory: viewModel)),
    );
    await tester.pump();

    expect(find.byKey(const Key('conversation-voice-button')), findsNothing);
  });

  testWidgets('the microphone button opens and closes the ears', (
    WidgetTester tester,
  ) async {
    final FakeVoiceService voice = FakeVoiceService();
    addTearDown(voice.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ConversationView(
          viewModelFactory: viewModel,
          voiceService: voice,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('conversation-voice-button')));
    await tester.pump();
    expect(voice.calls, contains('startListening'));

    await tester.tap(find.byKey(const Key('conversation-voice-button')));
    await tester.pump();
    expect(voice.calls, contains('stopListening'));
  });

  testWidgets('what is being heard shows over the composer', (
    WidgetTester tester,
  ) async {
    final FakeVoiceService voice = FakeVoiceService();
    addTearDown(voice.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ConversationView(
          viewModelFactory: viewModel,
          voiceService: voice,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('conversation-voice-button')));
    await tester.pump();

    voice.hear(const PartialTranscript('what time is'));
    await tester.pump();

    expect(find.text('what time is'), findsOneWidget);
  });

  testWidgets('a dead pipeline says why over the composer', (
    WidgetTester tester,
  ) async {
    final FakeVoiceService voice = FakeVoiceService();
    addTearDown(voice.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ConversationView(
          viewModelFactory: viewModel,
          voiceService: voice,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('conversation-voice-button')));
    await tester.pump();

    voice.hear(const VoiceFailed('the microphone went away'));
    await tester.pump();

    expect(
      find.byKey(const Key('conversation-voice-failure')),
      findsOneWidget,
      reason: 'The button went dark with no explanation.',
    );
    expect(find.textContaining('the microphone went away'), findsOneWidget);
  });
}
