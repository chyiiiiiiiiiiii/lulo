import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/conversation_repository.dart';
import 'package:local_agent_macos/features/conversation/conversation_view.dart';
import 'package:local_agent_macos/features/conversation/conversation_view_model.dart';

import '../../support/controlled_inference_service.dart';
import '../../support/recording_conversation_storage_service.dart';

void main() {
  testWidgets('a token delta rebuilds only the active streaming turn', (
    tester,
  ) async {
    final storage = RecordingConversationStorageService();
    final inference = ControlledInferenceService();
    final repository = ConversationRepository(
      storageService: storage,
      inferenceService: inference,
    );
    final viewModel = ConversationViewModel(
      repository: repository,
      idFactory: () => const ConversationId('conversation-1'),
    );
    final ConversationBuildObserver observer = ConversationBuildObserver();
    await tester.pumpWidget(
      MaterialApp(
        home: ConversationView(
          viewModelFactory: () => viewModel,
          buildObserver: observer,
        ),
      ),
    );
    await viewModel.submit('Hello');
    await inference.requestReceived;
    inference.emit(
      GenerationStarted(
        const Generation(
          id: GenerationId('generation-1'),
          request: GenerationRequest(
            conversationId: ConversationId('conversation-1'),
            prompt: 'Hello',
          ),
        ),
      ),
    );
    await tester.pump();
    observer.reset();

    inference.emit(
      const GenerationDelta(
        generationId: GenerationId('generation-1'),
        delta: 'A',
      ),
    );
    await tester.pump();

    expect(observer.activeStreamingTurnBuilds, 1);
    expect(observer.completedTurnsBuilds, 0);
    expect(observer.composerBuilds, 0);
    expect(observer.conversationListBuilds, 0);
    expect(observer.chromeBuilds, 0);
    expect(observer.modelStatusBuilds, 0);
    expect(find.text('A'), findsOneWidget);

    inference.emit(const GenerationCompleted(GenerationId('generation-1')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
