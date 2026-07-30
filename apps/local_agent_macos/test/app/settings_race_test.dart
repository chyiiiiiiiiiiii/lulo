import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/app.dart';
import 'package:local_agent_macos/app/app_composition.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';
import 'package:local_agent_macos/features/settings/app_settings.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';

import '../support/controlled_inference_service.dart';
import '../support/fake_presentation_host.dart';

/// A store whose load completes only when the test says so.
final class _GatedSettingsStore implements SettingsStore {
  _GatedSettingsStore(this._stored);

  final AppSettings _stored;

  /// Held until the test releases the load.
  final Completer<void> gate = Completer<void>();

  /// Everything the app wrote back, in order.
  final List<AppSettings> saved = <AppSettings>[];

  @override
  Future<AppSettings> load() async {
    await gate.future;
    return _stored;
  }

  @override
  Future<void> save(AppSettings settings) async {
    saved.add(settings);
  }
}

void main() {
  testWidgets('settings wait for what is stored before letting hands on', (
    WidgetTester tester,
  ) async {
    // The sheet applies each flip as it is made over the *current* settings.
    // A sheet opened before the stored ones arrive is a sheet over the
    // defaults: one flip would save defaults-plus-that-flip, silently
    // erasing the chosen model and every other stored choice.
    final _GatedSettingsStore store = _GatedSettingsStore(
      const AppSettings(
        modelPath: '/their/own/model.litertlm',
        keepOrbOnTop: false,
      ),
    );
    final FakePresentationHost host = FakePresentationHost();
    final AppComposition composition = AppComposition(
      () {},
      storageService: InMemoryConversationStorageService(),
      inferenceService: ControlledInferenceService(),
      presentationHost: host,
      settingsStore: store,
    );
    addTearDown(() => unawaited(composition.dispose()));

    host.presentation.value = DesktopPresentation.expanded;
    await tester.pumpWidget(
      LocalAgentApp(
        composition: composition,
        presenceShaderLoader: failShaderLoad,
      ),
    );
    await tester.pump();
    await tester.pump();

    // Asked for while the stored settings are still on their way.
    host.requestSettings();
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const Key('settings-sheet')),
      findsNothing,
      reason: 'The sheet opened over defaults the store had not confirmed.',
    );

    store.gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('settings-sheet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('setting-keep-orb-on-top')));
    await tester.pump();
    expect(
      store.saved.last.modelPath,
      '/their/own/model.litertlm',
      reason: 'A flip made on the sheet erased the stored model choice.',
    );
    expect(store.saved.last.keepOrbOnTop, isTrue);
  });
}
