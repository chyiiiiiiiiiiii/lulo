import 'dart:io';

Future<void> main() async {
  await _testUsage();
  await _testMissingDylibUsesStableError();
  await _testUnlinkedExecutableUsesStableError();
  await _testUnresolvableRpathUsesStableError();
  await _testUnsignedBundleUsesStableError();
  await _testSignedLinkedBundlePasses();
  await _testLaunchSmokeRejectsImmediateExit();
  await _testLaunchSmokePassesForRunningApp();
  await _testLaunchFailureUsesStableError();
  await _testUnknownOptionUsesStableUsageError();
  stdout.writeln('verify_litert_app_bundle_test: PASS');
}

Future<void> _testUsage() async {
  final ProcessResult result = await Process.run(
    Platform.resolvedExecutable,
    <String>['tool/verify_litert_app_bundle.dart'],
  );

  _expectEqual(result.exitCode, 64, 'usage exit code');
  _expectEqual(
    result.stderr,
    'bundle-smoke-error: expected <app-path> [--launch-smoke].\n',
    'usage error',
  );
}

Future<void> _testMissingDylibUsesStableError() async {
  final Directory fixture = Directory.systemTemp.createTempSync(
    'litert-bundle-smoke-secret-',
  );
  final Directory app = Directory('${fixture.path}/private-secret.app')
    ..createSync();
  try {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['tool/verify_litert_app_bundle.dart', app.path],
    );

    _expectEqual(result.exitCode, 1, 'missing dylib exit code');
    _expectEqual(
      result.stderr,
      'bundle-smoke-error: LiteRT-LM dylib is missing.\n',
      'missing dylib error',
    );
    _expectFalse(
      result.stderr.toString().contains(fixture.path),
      'missing dylib error leaked fixture path',
    );
  } finally {
    fixture.deleteSync(recursive: true);
  }
}

Future<void> _testUnlinkedExecutableUsesStableError() async {
  final Directory fixture = Directory.systemTemp.createTempSync(
    'litert-bundle-smoke-unlinked-secret-',
  );
  try {
    final Directory app = _createUnlinkedApp(fixture);
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['tool/verify_litert_app_bundle.dart', app.path],
    );

    _expectEqual(result.exitCode, 1, 'unlinked executable exit code');
    _expectEqual(
      result.stderr,
      'bundle-smoke-error: main executable does not link LiteRT-LM.\n',
      'unlinked executable error',
    );
    _expectFalse(
      result.stderr.toString().contains(fixture.path),
      'unlinked executable error leaked fixture path',
    );
  } finally {
    fixture.deleteSync(recursive: true);
  }
}

Future<void> _testUnresolvableRpathUsesStableError() async {
  final Directory fixture = Directory.systemTemp.createTempSync(
    'litert-bundle-smoke-rpath-secret-',
  );
  try {
    final Directory app = _createLinkedApp(
      fixture,
      rpath: '@executable_path/../Nowhere',
    );
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['tool/verify_litert_app_bundle.dart', app.path],
    );

    _expectEqual(result.exitCode, 1, 'unresolvable rpath exit code');
    _expectEqual(
      result.stderr,
      'bundle-smoke-error: LiteRT-LM load path is not resolvable '
          'inside app bundle.\n',
      'unresolvable rpath error',
    );
    _expectFalse(
      result.stderr.toString().contains(fixture.path),
      'unresolvable rpath error leaked fixture path',
    );
  } finally {
    fixture.deleteSync(recursive: true);
  }
}

Future<void> _testUnsignedBundleUsesStableError() async {
  final Directory fixture = Directory.systemTemp.createTempSync(
    'litert-bundle-smoke-signature-secret-',
  );
  try {
    final Directory app = _createLinkedApp(
      fixture,
      rpath: '@executable_path/../Frameworks',
    );
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['tool/verify_litert_app_bundle.dart', app.path],
    );

    _expectEqual(result.exitCode, 1, 'unsigned bundle exit code');
    _expectEqual(
      result.stderr,
      'bundle-smoke-error: app bundle code signature is invalid.\n',
      'unsigned bundle error',
    );
    _expectFalse(
      result.stderr.toString().contains(fixture.path),
      'unsigned bundle error leaked fixture path',
    );
  } finally {
    fixture.deleteSync(recursive: true);
  }
}

Future<void> _testSignedLinkedBundlePasses() async {
  final Directory fixture = Directory.systemTemp.createTempSync(
    'litert-bundle-smoke-valid-',
  );
  try {
    final Directory app = _createLinkedApp(
      fixture,
      rpath: '@executable_path/../Frameworks',
    );
    _runFixtureCommand('/usr/bin/codesign', <String>[
      '--force',
      '--sign',
      '-',
      '--deep',
      app.path,
    ]);
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['tool/verify_litert_app_bundle.dart', app.path],
    );

    _expectEqual(result.exitCode, 0, 'signed bundle exit code');
    _expectEqual(
      result.stdout,
      'LiteRT-LM app bundle smoke passed.\n',
      'signed bundle output',
    );
    _expectEqual(result.stderr, '', 'signed bundle error');
  } finally {
    fixture.deleteSync(recursive: true);
  }
}

Future<void> _testLaunchSmokeRejectsImmediateExit() async {
  final Directory fixture = Directory.systemTemp.createTempSync(
    'litert-bundle-smoke-launch-secret-',
  );
  try {
    final Directory app = _createLinkedApp(
      fixture,
      rpath: '@executable_path/../Frameworks',
    );
    _runFixtureCommand('/usr/bin/codesign', <String>[
      '--force',
      '--sign',
      '-',
      '--deep',
      app.path,
    ]);
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        'tool/verify_litert_app_bundle.dart',
        app.path,
        '--launch-smoke',
      ],
    );

    _expectEqual(result.exitCode, 1, 'launch smoke exit code');
    _expectEqual(
      result.stderr,
      'bundle-smoke-error: app exited during launch smoke.\n',
      'launch smoke error',
    );
    _expectFalse(
      result.stderr.toString().contains(fixture.path),
      'launch smoke error leaked fixture path',
    );
  } finally {
    fixture.deleteSync(recursive: true);
  }
}

Future<void> _testLaunchSmokePassesForRunningApp() async {
  final Directory fixture = Directory.systemTemp.createTempSync(
    'litert-bundle-smoke-running-',
  );
  try {
    final Directory app = _createLinkedApp(
      fixture,
      rpath: '@executable_path/../Frameworks',
      stayAlive: true,
    );
    _runFixtureCommand('/usr/bin/codesign', <String>[
      '--force',
      '--sign',
      '-',
      '--deep',
      app.path,
    ]);
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        'tool/verify_litert_app_bundle.dart',
        app.path,
        '--launch-smoke',
      ],
    );

    _expectEqual(result.exitCode, 0, 'running launch smoke exit code');
    _expectEqual(
      result.stdout,
      'LiteRT-LM app bundle launch smoke passed.\n',
      'running launch smoke output',
    );
    _expectEqual(result.stderr, '', 'running launch smoke error');
  } finally {
    fixture.deleteSync(recursive: true);
  }
}

Future<void> _testLaunchFailureUsesStableError() async {
  final Directory fixture = Directory.systemTemp.createTempSync(
    'litert-bundle-smoke-unlaunchable-secret-',
  );
  try {
    final Directory app = _createLinkedApp(
      fixture,
      rpath: '@executable_path/../Frameworks',
    );
    _runFixtureCommand('/usr/bin/codesign', <String>[
      '--force',
      '--sign',
      '-',
      '--deep',
      app.path,
    ]);
    _runFixtureCommand('/bin/chmod', <String>[
      '0644',
      '${app.path}/Contents/MacOS/Runner',
    ]);
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        'tool/verify_litert_app_bundle.dart',
        app.path,
        '--launch-smoke',
      ],
    );

    _expectEqual(result.exitCode, 1, 'launch failure exit code');
    _expectEqual(
      result.stderr,
      'bundle-smoke-error: app could not be launched.\n',
      'launch failure error',
    );
    _expectFalse(
      result.stderr.toString().contains(fixture.path),
      'launch failure error leaked fixture path',
    );
  } finally {
    fixture.deleteSync(recursive: true);
  }
}

Future<void> _testUnknownOptionUsesStableUsageError() async {
  final ProcessResult result =
      await Process.run(Platform.resolvedExecutable, <String>[
        'tool/verify_litert_app_bundle.dart',
        '/private/secret.app',
        '--secret-option',
      ]);

  _expectEqual(result.exitCode, 64, 'unknown option exit code');
  _expectEqual(
    result.stderr,
    'bundle-smoke-error: expected <app-path> [--launch-smoke].\n',
    'unknown option error',
  );
  _expectFalse(
    result.stderr.toString().contains('/private/secret.app'),
    'unknown option error leaked app path',
  );
}

Directory _createUnlinkedApp(Directory fixture) {
  final Directory app = Directory('${fixture.path}/Unlinked.app');
  final Directory frameworks = Directory('${app.path}/Contents/Frameworks')
    ..createSync(recursive: true);
  final Directory macOS = Directory('${app.path}/Contents/MacOS')
    ..createSync(recursive: true);
  File(
    '${frameworks.path}/libCLiteRTLM_mac.dylib',
  ).writeAsBytesSync(const <int>[0]);
  File('/usr/bin/true').copySync('${macOS.path}/Runner');
  File('${app.path}/Contents/Info.plist').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Runner</string>
  <key>CFBundleIdentifier</key>
  <string>test.bundle-smoke.unlinked</string>
</dict>
</plist>
''');
  return app;
}

Directory _createLinkedApp(
  Directory fixture, {
  required String rpath,
  bool stayAlive = false,
}) {
  final Directory app = Directory('${fixture.path}/Linked.app');
  final Directory frameworks = Directory('${app.path}/Contents/Frameworks')
    ..createSync(recursive: true);
  final Directory macOS = Directory('${app.path}/Contents/MacOS')
    ..createSync(recursive: true);
  final File dylibSource = File('${fixture.path}/litert_fixture.c')
    ..writeAsStringSync('int litert_probe(void) { return 42; }\n');
  final File mainSource = File('${fixture.path}/main_fixture.c')
    ..writeAsStringSync(
      stayAlive
          ? '''
#include <unistd.h>
int litert_probe(void);
int main(void) {
  if (litert_probe() != 42) { return 1; }
  sleep(3);
  return 0;
}
'''
          : '''
int litert_probe(void);
int main(void) { return litert_probe() == 42 ? 0 : 1; }
''',
    );
  final String dylibPath = '${frameworks.path}/libCLiteRTLM_mac.dylib';
  _runFixtureCommand('/usr/bin/clang', <String>[
    '-dynamiclib',
    dylibSource.path,
    '-Wl,-install_name,@rpath/libCLiteRTLM_mac.dylib',
    '-o',
    dylibPath,
  ]);
  _runFixtureCommand('/usr/bin/clang', <String>[
    mainSource.path,
    '-L${frameworks.path}',
    '-lCLiteRTLM_mac',
    '-Wl,-rpath,$rpath',
    '-o',
    '${macOS.path}/Runner',
  ]);
  File('${app.path}/Contents/Info.plist').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Runner</string>
  <key>CFBundleIdentifier</key>
  <string>test.bundle-smoke.linked</string>
</dict>
</plist>
''');
  return app;
}

void _runFixtureCommand(String executable, List<String> arguments) {
  final ProcessResult result = Process.runSync(executable, arguments);
  if (result.exitCode == 0) {
    return;
  }
  stderr.writeln('fixture command failed.');
  exit(1);
}

void _expectEqual(Object? actual, Object? expected, String label) {
  if (actual == expected) {
    return;
  }
  stderr.writeln('$label mismatch.');
  stderr.writeln('Expected: $expected');
  stderr.writeln('Actual: $actual');
  exit(1);
}

void _expectFalse(bool actual, String label) {
  if (!actual) {
    return;
  }
  stderr.writeln(label);
  exit(1);
}
