import 'dart:async';
import 'dart:io';

/// Runs the CP0 quality gate from the workspace root.
Future<void> main() async {
  final Directory workspaceRoot = Directory.current;
  final List<_VerificationCommand> commands = <_VerificationCommand>[
    _VerificationCommand(
      name: 'format',
      executable: 'dart',
      arguments: const <String>['format', '--set-exit-if-changed', '.'],
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

  final List<_VerificationResult> results = <_VerificationResult>[];
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
