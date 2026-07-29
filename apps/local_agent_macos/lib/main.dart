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
  runApp(
    LocalAgentApp(
      composition: createAppComposition(
        settingsStore: store,
        inferenceRuntime: hasModel ? 'litert' : 'fake',
        localModelPath: settings.modelPath,
      ),
    ),
  );
}
