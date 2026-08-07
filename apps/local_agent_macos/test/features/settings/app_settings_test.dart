import 'dart:convert';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/settings/app_settings.dart';

void main() {
  test('the chosen voice survives the round trip', () {
    const AppSettings settings = AppSettings(ttsVoice: 'vivian');
    final AppSettings reloaded = AppSettings.fromJson(settings.toJson());
    expect(reloaded.ttsVoice, 'vivian');
    expect(const AppSettings().ttsVoice, 'ryan');
    expect(settings.copyWith(ttsVoice: 'dylan').ttsVoice, 'dylan');
  });

  test('an untouched install rests on the desktop, above other work', () {
    const AppSettings settings = AppSettings();

    // The agent is a presence on the desktop before it is a window, so it
    // starts resting rather than open, and stays reachable over whatever the
    // user is working in.
    expect(settings.keepOrbOnTop, isTrue);
    expect(settings.followAcrossSpaces, isTrue);
    expect(settings.openConversationOnLaunch, isFalse);
  });

  test('an untouched install has no model and says so', () {
    // Empty is not a missing setting: it means the preview, which answers the
    // same thing every time. Naming a model is what makes the agent think.
    expect(const AppSettings().modelPath, isEmpty);
  });

  test('choices survive being written and read back', () async {
    final Directory directory = await _tempDirectory();
    final FileSettingsStore store = FileSettingsStore(directory: directory);
    const AppSettings chosen = AppSettings(
      keepOrbOnTop: false,
      followAcrossSpaces: false,
      openConversationOnLaunch: true,
      modelPath: '/models/gemma.litertlm',
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

  test('the answer style survives being written and read back', () {
    const AppSettings written = AppSettings(answerStyle: AnswerStyle.steady);

    expect(
      AppSettings.fromJson(written.toJson()).answerStyle,
      AnswerStyle.steady,
    );
    // A file written before this setting existed still opens, on the value
    // the app already shipped.
    expect(
      AppSettings.fromJson(const <String, Object?>{}).answerStyle,
      AnswerStyle.balanced,
    );
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
