import 'dart:io';

import 'macos_app_bundle.dart';

Future<void> main() async {
  _testReadsProductNameFromRealAppInfo();
  _testTrimsSurroundingWhitespace();
  _testStripsQuotes();
  _testIgnoresCommentedAssignments();
  _testIgnoresKeysThatMerelyStartWithProductName();
  _testMissingKeyUsesStableError();
  _testMissingFileUsesStableError();
  _testBundlePathComposesFromProductName();
  stdout.writeln('macos_app_bundle_test: PASS');
}

/// The repository's own configuration must resolve, or the gate is pointing at
/// a bundle that no longer exists.
void _testReadsProductNameFromRealAppInfo() {
  _expectEqual(
    readProductName(File(defaultAppInfoConfigPath(Directory.current.path))),
    'Lulo',
    'real AppInfo.xcconfig product name',
  );
}

void _testTrimsSurroundingWhitespace() {
  _withConfig('  PRODUCT_NAME   =   Spaced   \n', (File config) {
    _expectEqual(readProductName(config), 'Spaced', 'trimmed product name');
  });
}

void _testStripsQuotes() {
  _withConfig('PRODUCT_NAME = "Two Words"\n', (File config) {
    _expectEqual(readProductName(config), 'Two Words', 'unquoted product name');
  });
}

void _testIgnoresCommentedAssignments() {
  _withConfig('// PRODUCT_NAME = Stale\nPRODUCT_NAME = Current\n', (
    File config,
  ) {
    _expectEqual(readProductName(config), 'Current', 'uncommented wins');
  });
}

/// `PRODUCT_NAME_PREFIX` must not be mistaken for `PRODUCT_NAME`; a substring
/// match here would silently resolve the gate to the wrong bundle.
void _testIgnoresKeysThatMerelyStartWithProductName() {
  _withConfig('PRODUCT_NAME_PREFIX = Wrong\nPRODUCT_NAME = Right\n', (
    File config,
  ) {
    _expectEqual(readProductName(config), 'Right', 'exact key match');
  });
}

void _testMissingKeyUsesStableError() {
  _withConfig('PRODUCT_BUNDLE_IDENTIFIER = com.example\n', (File config) {
    _expectThrowsMessage(
      () => readProductName(config),
      'PRODUCT_NAME is not declared in the app configuration.',
      'missing key error',
    );
  });
}

void _testMissingFileUsesStableError() {
  final Directory fixture = Directory.systemTemp.createTempSync(
    'macos-app-bundle-secret-',
  );
  try {
    _expectThrowsMessage(
      () => readProductName(File('${fixture.path}/absent.xcconfig')),
      'app configuration file is missing.',
      'missing file error',
    );
  } finally {
    fixture.deleteSync(recursive: true);
  }
}

void _testBundlePathComposesFromProductName() {
  _expectEqual(
    macosAppBundlePath(
      workspaceRoot: '/w',
      configuration: 'Profile',
      productName: 'Lulo',
    ),
    '/w/apps/local_agent_macos/build/macos/Build/Products/Profile/Lulo.app',
    'composed bundle path',
  );
}

void _withConfig(String contents, void Function(File config) body) {
  final Directory fixture = Directory.systemTemp.createTempSync(
    'macos-app-bundle-',
  );
  try {
    final File config = File('${fixture.path}/AppInfo.xcconfig')
      ..writeAsStringSync(contents);
    body(config);
  } finally {
    fixture.deleteSync(recursive: true);
  }
}

void _expectEqual(Object? actual, Object? expected, String label) {
  if (actual != expected) {
    stderr.writeln('$label: expected <$expected>, got <$actual>');
    exit(1);
  }
}

void _expectThrowsMessage(
  void Function() body,
  String expectedMessage,
  String label,
) {
  try {
    body();
  } on FormatException catch (error) {
    _expectEqual(error.message, expectedMessage, label);
    return;
  }
  stderr.writeln('$label: expected a FormatException, none was thrown');
  exit(1);
}
