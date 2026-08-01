import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/agent_profile/agent_profile_store.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lulo-profile-');
    file = File('${directory.path}/agent_profile.json');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('a missing profile starts with built-in behavior', () async {
    final FileAgentProfileStore store = FileAgentProfileStore(
      file: file,
      watch: false,
    );
    addTearDown(store.dispose);

    await store.load();

    expect(store.current.identity.agentName, 'Lulo');
    expect(store.error, isNull);
  });

  test('a valid profile loads from the real file', () async {
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'identity': <String, Object?>{'userName': 'Yii'},
      }),
    );
    final FileAgentProfileStore store = FileAgentProfileStore(
      file: file,
      watch: false,
    );
    addTearDown(store.dispose);

    await store.load();

    expect(store.current.identity.userName, 'Yii');
    expect(store.revision.value, 1);
  });

  test('a malformed change retains the last valid profile', () async {
    await file.writeAsString(
      '{"schemaVersion":1,"identity":{"userName":"Yii"}}',
    );
    final FileAgentProfileStore store = FileAgentProfileStore(
      file: file,
      watch: true,
      debounce: const Duration(milliseconds: 20),
    );
    addTearDown(store.dispose);
    await store.load();
    final int validRevision = store.revision.value;

    await file.writeAsString('{broken');
    await _eventually(() => store.error != null);

    expect(store.current.identity.userName, 'Yii');
    expect(store.revision.value, greaterThan(validRevision));
  });

  test(
    'a valid change affects the next snapshot and deletion restores defaults',
    () async {
      final FileAgentProfileStore store = FileAgentProfileStore(
        file: file,
        watch: true,
        debounce: const Duration(milliseconds: 20),
      );
      addTearDown(store.dispose);
      await store.load();

      await file.writeAsString(
        '{"schemaVersion":1,"identity":{"userName":"Yii"}}',
      );
      await _eventually(() => store.current.identity.userName == 'Yii');

      await file.delete();
      await _eventually(() => store.current.identity.userName.isEmpty);

      expect(store.error, isNull);
    },
  );

  test('dispose prevents later file events changing the revision', () async {
    final FileAgentProfileStore store = FileAgentProfileStore(
      file: file,
      watch: true,
      debounce: const Duration(milliseconds: 20),
    );
    await store.load();
    await store.dispose();
    final int disposedRevision = store.revision.value;

    await file.writeAsString('{"schemaVersion":1}');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(store.revision.value, disposedRevision);
  });
}

Future<void> _eventually(bool Function() condition) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > const Duration(seconds: 2)) {
      fail('The file event was not observed within two seconds.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
