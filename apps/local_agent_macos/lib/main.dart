import 'dart:io';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'features/settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The model is chosen in settings rather than fixed when the app is built,
  // so it has to be read before anything is wired to it.
  final SettingsStore store = createSettingsStore();
  final AppSettings settings = await store.load();
  final bool hasModel = settings.modelPath.trim().isNotEmpty;
  // The native test suite runs inside this app, and the app shares its
  // settings with the one the user really uses — same bundle, same container.
  // Left alone it would start loading a multi-gigabyte model the moment the
  // test host launched, which starved the test runner's connection window
  // often enough to fail runs. The tests are about the window, not the model.
  final bool hostingTests = Platform.environment.keys.any(
    (String key) => key.startsWith('XCTest'),
  );
  runApp(
    LocalAgentApp(
      composition: createAppComposition(
        settingsStore: store,
        inferenceRuntime: hasModel && !hostingTests ? 'litert' : 'fake',
        localModelPath: settings.modelPath,
        // Same container as the real app: the test host stays on the
        // in-memory default so it never reads or writes the user's history.
        conversationStorage: hostingTests
            ? null
            : createDurableConversationStorage(),
      ),
    ),
  );
}
