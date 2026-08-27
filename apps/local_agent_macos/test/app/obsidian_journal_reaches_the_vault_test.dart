import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/app.dart';
import 'package:local_agent_macos/app/app_composition.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/settings/app_settings.dart';

import '../support/controlled_inference_service.dart';
import '../support/fake_presentation_host.dart';

/// The whole path from a finished answer to a file in the user's own notes.
///
/// The unit tests cover the format and the writer; this covers the wiring,
/// which is where "built and never connected to anything" lives.
Future<void> submit(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const Key('conversation-composer-field')),
    text,
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('conversation-submit-button')));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('a finished answer is appended to the day it happened', (
    WidgetTester tester,
  ) async {
    final FakePresentationHost host = FakePresentationHost()..vault = '/vault';
    final ControlledInferenceService inference = ControlledInferenceService();
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: inference,
      presentationHost: host,
      settingsStore: InMemorySettingsStore(
        const AppSettings(
          modelPath: '/models/gemma.litertlm',
          obsidianJournal: true,
        ),
      ),
    );
    addTearDown(() => unawaited(composition.dispose()));
    addTearDown(() => unawaited(inference.dispose()));
    await tester.pumpWidget(
      LocalAgentApp(
        composition: composition,
        presenceShaderLoader: failShaderLoad,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await submit(tester, '明天台中天氣如何');
    expect(inference.requests, isNotEmpty, reason: 'nothing was ever asked');
    final GenerationRequest asked = inference.requests.single;
    inference.emit(
      GenerationStarted(
        Generation(id: const GenerationId('generation-1'), request: asked),
      ),
    );
    await tester.pump();
    inference
      ..emit(
        const GenerationDelta(
          generationId: GenerationId('generation-1'),
          delta: '台中明天多雲。',
        ),
      )
      ..emit(const GenerationCompleted(GenerationId('generation-1')));
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // ignore: avoid_print
    print(
      'ENABLED ${composition.obsidianJournal.value} '
      'JOURNAL ${composition.journal != null} '
      'LAST ${composition.journal?.lastWrite.value} '
      'WRITES ${host.vaultWrites.length}',
    );
    expect(
      host.vaultWrites,
      isNotEmpty,
      reason: 'the mirror was built and never reached the vault',
    );
    expect(host.vaultWrites.single.fileName, endsWith('.md'));
    expect(host.vaultWrites.single.entry, contains('明天台中天氣如何'));
    expect(host.vaultWrites.single.entry, contains('台中明天多雲。'));
  });

  testWidgets('nothing is written while the user has not asked for it', (
    WidgetTester tester,
  ) async {
    final FakePresentationHost host = FakePresentationHost()..vault = '/vault';
    final ControlledInferenceService inference = ControlledInferenceService();
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: inference,
      presentationHost: host,
      settingsStore: InMemorySettingsStore(
        const AppSettings(modelPath: '/models/gemma.litertlm'),
      ),
    );
    addTearDown(() => unawaited(composition.dispose()));
    addTearDown(() => unawaited(inference.dispose()));
    await tester.pumpWidget(
      LocalAgentApp(
        composition: composition,
        presenceShaderLoader: failShaderLoad,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await submit(tester, '嗨');
    expect(inference.requests, isNotEmpty, reason: 'nothing was ever asked');
    final GenerationRequest asked = inference.requests.single;
    inference.emit(
      GenerationStarted(
        Generation(id: const GenerationId('generation-1'), request: asked),
      ),
    );
    await tester.pump();
    inference
      ..emit(
        const GenerationDelta(
          generationId: GenerationId('generation-1'),
          delta: '嗨。',
        ),
      )
      ..emit(const GenerationCompleted(GenerationId('generation-1')));
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(host.vaultWrites, isEmpty);
  });
}
