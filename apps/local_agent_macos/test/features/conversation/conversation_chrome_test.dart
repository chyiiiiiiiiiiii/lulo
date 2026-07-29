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

    // The conversation runs under a transparent titlebar, so its own chrome
    // starts after the close, minimise and zoom buttons rather than beneath
    // them.
    expect(
      tester.getTopLeft(find.text('Lulo')).dx,
      greaterThanOrEqualTo(_windowButtonsWidth),
      reason: 'The title was drawn underneath the window buttons.',
    );
  });
}

/// How much of the leading edge the standard window buttons occupy.
///
/// Three buttons starting near the leading edge and evenly spaced, plus the
/// gap that keeps the title from crowding the last of them.
const double _windowButtonsWidth = 70;

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
