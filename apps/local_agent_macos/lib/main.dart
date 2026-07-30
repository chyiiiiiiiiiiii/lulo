import 'dart:io';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'features/model/model_catalog.dart';
import 'features/settings/app_settings.dart';
import 'features/voice/pigeon_voice_service.dart';

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
  // Who speaks: kept in a notifier so a voice changed in settings applies
  // to the very next answer without rebuilding the service.
  final ValueNotifier<String> ttsVoice = ValueNotifier<String>(
    settings.ttsVoice,
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
        // An empty catalog in the test host: launch adoption would otherwise
        // find the user's installed model, load gigabytes into the test
        // runner's connection window, and write the adoption into the user's
        // own settings.
        catalog: hostingTests ? const <ModelCatalogEntry>[] : modelCatalog,
        // No ears in the test host — opening the microphone from a test run
        // would hang the runner on a permission dialog — and none below
        // macOS 26, where the native side has no transcriber to register: a
        // button would throw on every tap.
        // No ears in the test host — opening the microphone from a test run
        // would hang the runner on a permission dialog — and none below
        // macOS 26, where the native side has no transcriber to register: a
        // button would throw on every tap.
        voiceService: hostingTests || !_speechAnalyzerAvailable()
            ? null
            : PigeonVoiceService(voiceOf: () => ttsVoice.value),
        ttsVoice: ttsVoice,
      ),
    ),
  );
}

/// Whether this macOS carries SpeechAnalyzer (macOS 26 and newer).
bool _speechAnalyzerAvailable() {
  final RegExp major = RegExp(r'Version (\d+)');
  final Match? version = major.firstMatch(Platform.operatingSystemVersion);
  final int? parsed = version == null ? null : int.tryParse(version[1]!);
  return parsed != null && parsed >= 26;
}
