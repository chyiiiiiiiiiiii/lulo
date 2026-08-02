import 'dart:async';
import 'dart:io';

import 'macos_app_bundle.dart';

/// Runs the workspace quality gate from the workspace root.
Future<void> main() async {
  final Directory workspaceRoot = Directory.current;

  // Resolved from the checked-in app configuration rather than hard-coded,
  // because the built bundle is named after PRODUCT_NAME and the last rename
  // left a stale `local_agent_macos.app` sitting beside the current one: any
  // glob or literal here would happily verify the wrong bundle.
  String? appBundlePath;
  String? appBundleResolutionFailure;
  try {
    appBundlePath = macosAppBundlePath(
      workspaceRoot: workspaceRoot.path,
      configuration: 'Profile',
      productName: readProductName(
        File(defaultAppInfoConfigPath(workspaceRoot.path)),
      ),
    );
  } on FormatException catch (error) {
    appBundleResolutionFailure = error.message;
  }

  // `flutter build macos` rewrites App.framework on every run, but Xcode only
  // re-signs the outer bundle when the Runner target itself relinks. So an
  // incremental build leaves a signature sealing a framework that has since
  // changed, and codesign rightly calls the result `nested code is modified`.
  // Removing the product first makes the build assemble and sign in one pass,
  // the way a clean CI checkout always does. Measured at ~10s: this discards
  // the assembled bundle, not the compile caches that make it.
  if (appBundlePath != null) {
    final Directory staleBundle = Directory(appBundlePath);
    try {
      if (staleBundle.existsSync()) {
        staleBundle.deleteSync(recursive: true);
      }
    } on FileSystemException {
      appBundleResolutionFailure =
          'the previously built app bundle could not be removed.';
      appBundlePath = null;
    }
  }

  final List<_VerificationCommand> commands = <_VerificationCommand>[
    _VerificationCommand(
      name: 'format',
      executable: 'dart',
      arguments: const <String>['format', '--set-exit-if-changed', '.'],
      workingDirectory: workspaceRoot.path,
    ),
    // The root package is where `tool/` lives, and nothing here analysed it:
    // the gate's own scripts were the only Dart in the repo that could rot
    // unlinted.
    _VerificationCommand(
      name: 'workspace analysis',
      executable: 'dart',
      arguments: const <String>['analyze', '--fatal-infos', '--fatal-warnings'],
      workingDirectory: workspaceRoot.path,
    ),
    _VerificationCommand(
      name: 'core analysis',
      executable: 'dart',
      arguments: const <String>['analyze', '--fatal-infos', '--fatal-warnings'],
      workingDirectory: _join(workspaceRoot.path, 'packages/agent_core'),
    ),
    _VerificationCommand(
      name: 'app analysis',
      executable: 'flutter',
      arguments: const <String>['analyze', '--fatal-infos', '--fatal-warnings'],
      workingDirectory: _join(workspaceRoot.path, 'apps/local_agent_macos'),
    ),
    _VerificationCommand(
      name: 'core tests',
      executable: 'dart',
      arguments: const <String>['test'],
      workingDirectory: _join(workspaceRoot.path, 'packages/agent_core'),
    ),
    // The gate's own checks had tests that nothing ran, which is the same
    // trap the window tests fell into: a verifier that has quietly stopped
    // detecting anything still reports success.
    _VerificationCommand(
      name: 'app bundle path resolver tests',
      executable: 'dart',
      arguments: const <String>['tool/macos_app_bundle_test.dart'],
      workingDirectory: workspaceRoot.path,
    ),
    _VerificationCommand(
      name: 'LiteRT-LM app bundle gate tests',
      executable: 'dart',
      arguments: const <String>['tool/verify_litert_app_bundle_test.dart'],
      workingDirectory: workspaceRoot.path,
    ),
    _VerificationCommand(
      name: 'voice eval analysis',
      executable: 'dart',
      arguments: const <String>['analyze', '--fatal-infos', '--fatal-warnings'],
      workingDirectory: _join(workspaceRoot.path, 'benchmarks/voice_eval'),
    ),
    _VerificationCommand(
      name: 'voice eval tests',
      executable: 'dart',
      arguments: const <String>['test'],
      workingDirectory: _join(workspaceRoot.path, 'benchmarks/voice_eval'),
    ),
    _VerificationCommand(
      name: 'Qwen transcript sidecar tests',
      executable: 'python3',
      arguments: const <String>['-m', 'unittest', 'discover'],
      workingDirectory: _join(
        workspaceRoot.path,
        'sidecars/qwen_transcript_refiner',
      ),
    ),
    _VerificationCommand(
      name: 'Smart Turn shadow tests',
      executable: 'python3',
      arguments: const <String>['-m', 'unittest', 'discover'],
      workingDirectory: _join(workspaceRoot.path, 'sidecars/smart_turn_shadow'),
    ),
    _VerificationCommand(
      name: 'presence frame metrics tests',
      executable: 'flutter',
      arguments: const <String>[
        'test',
        'test/features/presence/agent_presence_frame_metrics_test.dart',
      ],
      workingDirectory: _join(workspaceRoot.path, 'apps/local_agent_macos'),
    ),
    _VerificationCommand(
      name: 'Flutter tests',
      executable: 'flutter',
      arguments: const <String>['test'],
      workingDirectory: _join(workspaceRoot.path, 'apps/local_agent_macos'),
    ),
    _VerificationCommand(
      name: 'macOS fake-runtime integration test',
      executable: 'flutter',
      arguments: const <String>[
        'test',
        'integration_test/conversation_vertical_slice_test.dart',
        '-d',
        'macos',
      ],
      workingDirectory: _join(workspaceRoot.path, 'apps/local_agent_macos'),
    ),
    _VerificationCommand(
      name: 'macOS profile build',
      executable: 'flutter',
      arguments: const <String>['build', 'macos', '--profile'],
      workingDirectory: _join(workspaceRoot.path, 'apps/local_agent_macos'),
    ),
    // Nothing linked the LiteRT-LM dylib check to the build that produces it,
    // so an app bundle that had lost the library, its @rpath, or its signature
    // still went green here — the one failure that makes every real-model path
    // fail at launch. It runs against the profile build directly above.
    //
    // Static checks only: --launch-smoke actually starts the app, and a window
    // opened from CI has already cost this repo hours (full-screen Space, TCC
    // prompts). Run that by hand when the launch path itself is in question.
    if (appBundlePath != null)
      _VerificationCommand(
        name: 'LiteRT-LM app bundle gate',
        executable: 'dart',
        arguments: <String>[
          'tool/verify_litert_app_bundle.dart',
          appBundlePath,
        ],
        workingDirectory: workspaceRoot.path,
      ),
    // The window is where this app's hardest bugs live, and its tests were
    // being written but never run: nothing here invoked them, so a rename of
    // the app quietly broke the test target and a click that went straight
    // through the resting orb was reported as covered. Run through the
    // workspace rather than the project, because the pods the app links are
    // only wired up there.
    //
    // Deliberately NOT into the build directory Flutter itself uses: two
    // build systems over one Products directory each mark the other's
    // outputs stale and delete them, while flutter assemble's fingerprint
    // stamps still say its native-assets are up to date. The first native
    // asset in the tree (drift's sqlite3) turned that quiet war into a
    // half-written sqlite3.framework and a codesign failure here.
    _VerificationCommand(
      name: 'macOS window tests',
      executable: 'xcodebuild',
      arguments: const <String>[
        'test',
        '-workspace',
        'Runner.xcworkspace',
        '-scheme',
        'Runner',
        '-configuration',
        'Debug',
        '-destination',
        'platform=macOS',
        '-derivedDataPath',
        '../build/macos_window_tests',
      ],
      workingDirectory: _join(
        workspaceRoot.path,
        'apps/local_agent_macos/macos',
      ),
    ),
  ];
  final File swiftPackage = File(
    _join(workspaceRoot.path, 'native/inference_service/Package.swift'),
  );
  if (swiftPackage.existsSync()) {
    commands.add(
      _VerificationCommand(
        name: 'Swift tests',
        executable: 'swift',
        arguments: const <String>['test'],
        workingDirectory: swiftPackage.parent.path,
      ),
    );
  }

  // A bundle path we could not resolve is reported as a failure rather than a
  // skipped step, so that renaming the app can never quietly retire the check.
  final List<_VerificationResult> results = <_VerificationResult>[
    if (appBundleResolutionFailure != null)
      _VerificationResult(
        name: 'LiteRT-LM app bundle gate',
        exitCode: 1,
        output: 'bundle-smoke-error: $appBundleResolutionFailure',
      ),
  ];
  for (final _VerificationCommand command in commands) {
    results.add(await _runCommand(command));
  }
  final List<_VerificationResult> failures = results
      .where((_VerificationResult result) => result.exitCode != 0)
      .toList();

  for (final _VerificationResult result in results) {
    stdout.writeln('[${result.name}] exit ${result.exitCode}');
    if (result.output.isNotEmpty) {
      stdout.writeln(result.output);
    }
  }

  if (failures.isNotEmpty) {
    stderr.writeln('${failures.length} verification subprocess(es) failed.');
    exitCode = 1;
  }
}

/// Runs one explicit verification subprocess and preserves its diagnostics.
Future<_VerificationResult> _runCommand(_VerificationCommand command) async {
  try {
    final ProcessResult processResult = await Process.run(
      command.executable,
      command.arguments,
      workingDirectory: command.workingDirectory,
    );
    final String output = <String>[
      processResult.stdout.toString().trim(),
      processResult.stderr.toString().trim(),
    ].where((String line) => line.isNotEmpty).join('\n');
    return _VerificationResult(
      name: command.name,
      exitCode: processResult.exitCode,
      output: output,
    );
  } on ProcessException catch (error) {
    return _VerificationResult(
      name: command.name,
      exitCode: 1,
      output: '$error',
    );
  }
}

/// Joins [childPath] to [parentPath] with the host platform separator.
String _join(String parentPath, String childPath) {
  return '$parentPath${Platform.pathSeparator}$childPath';
}

/// Describes one subprocess in the root verification fan-out.
final class _VerificationCommand {
  /// Creates a subprocess definition.
  const _VerificationCommand({
    required this.name,
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  /// A readable label for reporting failures.
  final String name;

  /// The executable to run.
  final String executable;

  /// Arguments passed to [executable].
  final List<String> arguments;

  /// Directory from which the executable runs.
  final String workingDirectory;
}

/// Captures the result of one verification subprocess.
final class _VerificationResult {
  /// Creates a reported subprocess result.
  const _VerificationResult({
    required this.name,
    required this.exitCode,
    required this.output,
  });

  /// The readable subprocess label.
  final String name;

  /// The subprocess result code.
  final int exitCode;

  /// Combined standard output and error diagnostics.
  final String output;
}
