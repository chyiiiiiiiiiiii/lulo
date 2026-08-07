import 'dart:convert';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/agent_profile/agent_profile_codec.dart';
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

  group('saving from the app', () {
    test('a saved profile is on disk and in force at once', () async {
      final FileAgentProfileStore store = FileAgentProfileStore(
        file: file,
        watch: false,
      );
      addTearDown(store.dispose);
      await store.load();
      final int before = store.revision.value;

      await store.save(
        AgentProfile(
          identity: const AgentIdentity(agentName: '露露', userName: 'Yii'),
          turnTaking: const TurnTakingWords(acknowledgements: <String>['蛤']),
        ),
      );

      // In force immediately rather than after the watcher notices. Watching
      // is off in release builds, and where it is on the debounce would leave
      // the screen showing the old profile for a quarter of a second after
      // the user changed it.
      expect(store.current.identity.agentName, '露露');
      expect(store.current.turnTaking.acknowledgements, <String>['蛤']);
      expect(store.revision.value, greaterThan(before));

      // And it is the file the developer edits by hand, still readable by
      // the same decoder.
      final AgentProfileDecodeResult reread = decodeAgentProfile(
        jsonDecode(await file.readAsString()),
      );
      expect(reread.error, isNull);
      expect(reread.profile, store.current);
    });

    test('saving into a directory that is gone still works', () async {
      // The user can delete Application Support between launches, and losing
      // a preference is not a reason to fail the save that follows.
      final File nested = File('${directory.path}/gone/agent_profile.json');
      final FileAgentProfileStore store = FileAgentProfileStore(
        file: nested,
        watch: false,
      );
      addTearDown(store.dispose);
      await store.load();

      await store.save(AgentProfile.builtIn());

      expect(nested.existsSync(), isTrue);
    });

    test('a disposed store does not write', () async {
      final FileAgentProfileStore store = FileAgentProfileStore(
        file: file,
        watch: false,
      );
      await store.load();
      await store.dispose();

      await expectLater(store.save(AgentProfile.builtIn()), throwsStateError);
      expect(file.existsSync(), isFalse);
    });

    test('a change made while a write is in flight is not undone', () async {
      // Every control on the settings sheet computes its next profile from
      // `current`. While a write was in flight `current` still held the
      // profile from before it, so a second change was built on the old one
      // and saving it put the first change back — two chips deleted quickly
      // and one of them returned.
      final Directory dir = await Directory.systemTemp.createTemp('lulo-race');
      addTearDown(() => dir.delete(recursive: true));
      final FileAgentProfileStore store = FileAgentProfileStore(
        file: File('${dir.path}/agent_profile.json'),
        watch: false,
      );
      addTearDown(store.dispose);
      await store.load();

      // Not awaited: this is the window the bug lived in.
      final Future<void> first = store.save(
        store.current.copyWith(vocabulary: const <String>['one']),
      );
      final Future<void> second = store.save(
        store.current.copyWith(
          misheard: const <MisheardWord>[MisheardWord(heard: 'a', meant: 'b')],
        ),
      );
      await Future.wait<void>(<Future<void>>[first, second]);

      expect(store.current.vocabulary, <String>['one']);
      expect(store.current.misheard, <MisheardWord>[
        const MisheardWord(heard: 'a', meant: 'b'),
      ]);
    });
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
