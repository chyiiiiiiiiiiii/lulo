import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/conversation_repository.dart';
import 'package:local_agent_macos/features/conversation/conversation_view.dart';
import 'package:local_agent_macos/features/conversation/conversation_view_model.dart';

import '../../support/controlled_inference_service.dart';
import '../../support/recording_conversation_storage_service.dart';

void main() {
  testWidgets('the conversation leaves the window buttons room to sit', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ConversationView(viewModelFactory: _viewModel),
        ),
      ),
    );
    await tester.pump();

    // The window buttons live on the line above the title, so the title sits
    // flush with the content's own margin. Indenting it their width left a
    // hole in the header with nothing in it.
    expect(
      tester.getTopLeft(find.text('Lulo')).dx,
      24,
      reason: 'The title is not flush with the content margin.',
    );
  });
}

ConversationViewModel _viewModel() {
  final RecordingConversationStorageService storage =
      RecordingConversationStorageService();
  final ControlledInferenceService inference = ControlledInferenceService();
  return ConversationViewModel(
    repository: ConversationRepository(
      storageService: storage,
      inferenceService: inference,
    ),
    idFactory: () => const ConversationId('conversation-1'),
  );
}
