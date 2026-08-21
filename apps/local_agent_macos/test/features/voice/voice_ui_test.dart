import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/conversation/conversation_repository.dart';
import 'package:local_agent_macos/features/conversation/conversation_view.dart';
import 'package:local_agent_macos/features/conversation/conversation_view_model.dart';
import 'package:local_agent_macos/features/voice/voice_service.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

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
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConversationView(viewModelFactory: viewModel),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('conversation-voice-button')), findsNothing);
  });

  testWidgets('the always-on toggle hides until its setting turns it on', (
    WidgetTester tester,
  ) async {
    // The open microphone is opt-in now: holding to talk is the product's
    // answer, and a toggle that opens an always-listening, audio-ducking
    // session has to be asked for in Settings before it is offered at all.
    final FakeVoiceService voice = FakeVoiceService();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConversationView(
          viewModelFactory: viewModel,
          voiceService: voice,
        ),
      ),
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConversationView(
          liveConversationToggle: true,
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConversationView(
          liveConversationToggle: true,
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

  testWidgets('listening shows itself while nothing is being heard', (
    WidgetTester tester,
  ) async {
    // "Nothing happening" and "listening for you" must not look the same.
    final FakeVoiceService voice = FakeVoiceService();
    addTearDown(voice.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConversationView(
          liveConversationToggle: true,
          viewModelFactory: viewModel,
          voiceService: voice,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('conversation-listening')), findsNothing);

    await tester.tap(find.byKey(const Key('conversation-voice-button')));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('conversation-listening')),
      findsOneWidget,
      reason: 'An open microphone gave no sign of itself.',
    );

    voice.hear(const PartialTranscript('what time'));
    await tester.pump();
    expect(find.byKey(const Key('conversation-listening')), findsNothing);
    expect(find.text('what time'), findsOneWidget);
  });

  testWidgets('the status says which of the three silences this is', (
    WidgetTester tester,
  ) async {
    // In full duplex the microphone never closes, so "Listening…" is true
    // the whole time and tells the user nothing. A silent window could be
    // thinking, could be talking too quietly to hear, could be broken —
    // and for one real session it was the third.
    final FakeVoiceService voice = FakeVoiceService();
    addTearDown(voice.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Pinned, because the strings this test reads are the point of it.
        // The app itself follows the system; a test that took the harness's
        // default would be asserting the harness's language.
        locale: const Locale('zh'),
        home: ConversationView(
          liveConversationToggle: true,
          viewModelFactory: viewModel,
          voiceService: voice,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('conversation-voice-button')));
    await tester.pump();
    await tester.pump();

    expect(find.text('聆聽中…'), findsOneWidget);

    // A question is asked: the agent is now thinking, not merely listening.
    voice.hear(const FinalTranscript('Tell me something.'));
    await tester.pump();
    await tester.pump();
    expect(find.text('思考中…'), findsOneWidget);
    expect(find.text('聆聽中…'), findsNothing);
  });

  testWidgets('a dead pipeline says why over the composer', (
    WidgetTester tester,
  ) async {
    final FakeVoiceService voice = FakeVoiceService();
    addTearDown(voice.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConversationView(
          liveConversationToggle: true,
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
