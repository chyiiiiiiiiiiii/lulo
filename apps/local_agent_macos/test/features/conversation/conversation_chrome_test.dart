import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/conversation_repository.dart';
import 'package:local_agent_macos/features/conversation/conversation_view.dart';
import 'package:local_agent_macos/features/conversation/conversation_view_model.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

import '../../support/controlled_inference_service.dart';
import '../../support/recording_conversation_storage_service.dart';

void main() {
  testWidgets('the conversation leaves the window buttons room to sit', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ConversationView(viewModelFactory: _viewModel),
        ),
      ),
    );
    await tester.pump();

    // The window buttons live on the line above the title, so the title sits
    // on the content column's own edge — which is the composer's edge.
    expect(
      tester.getTopLeft(find.text('Lulo')).dx,
      tester
          .getTopLeft(find.byKey(const Key('conversation-composer-field')))
          .dx,
      reason: 'The title and the composer do not share a leading edge.',
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
