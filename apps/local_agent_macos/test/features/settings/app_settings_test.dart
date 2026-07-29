import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/settings/app_settings.dart';

void main() {
  test('an untouched install rests on the desktop, above other work', () {
    const AppSettings settings = AppSettings();

    // The agent is a presence on the desktop before it is a window, so it
    // starts resting rather than open, and stays reachable over whatever the
    // user is working in.
    expect(settings.keepOrbOnTop, isTrue);
    expect(settings.followAcrossSpaces, isTrue);
    expect(settings.openConversationOnLaunch, isFalse);
  });

  test('choices survive being written and read back', () async {
    final Directory directory = await _tempDirectory();
    final FileSettingsStore store = FileSettingsStore(directory: directory);
    const AppSettings chosen = AppSettings(
      keepOrbOnTop: false,
      followAcrossSpaces: false,
      openConversationOnLaunch: true,
    );

    await store.save(chosen);

    expect(await store.load(), chosen);
  });

  test(
    'a first run has nothing to read and starts from the defaults',
    () async {
      final Directory directory = await _tempDirectory();

      expect(
        await FileSettingsStore(directory: directory).load(),
        const AppSettings(),
      );
    },
  );

  test('a damaged settings file does not take the app down with it', () async {
    final Directory directory = await _tempDirectory();
    final FileSettingsStore store = FileSettingsStore(directory: directory);
    await store.save(const AppSettings());
    await store.file.writeAsString('{ this is not json');

    // Settings are a convenience. Failing to read them must cost the user
    // their preferences, never their agent.
    expect(await store.load(), const AppSettings());
  });

  test('a setting written by a later version is ignored, not fatal', () async {
    final Directory directory = await _tempDirectory();
    final FileSettingsStore store = FileSettingsStore(directory: directory);
    await store.file.writeAsString(
      jsonEncode(<String, Object?>{
        'keepOrbOnTop': false,
        'somethingFromTheFuture': 'unknown',
      }),
    );

    final AppSettings loaded = await store.load();

    expect(loaded.keepOrbOnTop, isFalse);
    expect(loaded.followAcrossSpaces, isTrue);
  });
}

Future<Directory> _tempDirectory() async {
  final Directory directory = await Directory.systemTemp.createTemp(
    'pocket-agent-settings',
  );
  addTearDown(() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });
  return directory;
}
