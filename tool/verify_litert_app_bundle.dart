import 'dart:async';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty ||
      arguments.length > 2 ||
      (arguments.length == 2 && arguments[1] != '--launch-smoke')) {
    _fail('expected <app-path> [--launch-smoke].', exitCode: 64);
  }

  final String appPath = arguments.first;
  final File dylib = File(
    '$appPath/Contents/Frameworks/libCLiteRTLM_mac.dylib',
  );
  if (!dylib.existsSync()) {
    _fail('LiteRT-LM dylib is missing.');
  }

  final ProcessResult plist = await Process.run('/usr/bin/plutil', <String>[
    '-extract',
    'CFBundleExecutable',
    'raw',
    '-o',
    '-',
    '$appPath/Contents/Info.plist',
  ]);
  if (plist.exitCode != 0) {
    _fail('main executable could not be determined.');
  }
  final File executable = File(
    '$appPath/Contents/MacOS/${plist.stdout.toString().trim()}',
  );
  if (!executable.existsSync()) {
    _fail('main executable could not be determined.');
  }

  final ProcessResult linkedLibraries = await Process.run(
    '/usr/bin/otool',
    <String>['-L', executable.path],
  );
  final RegExp liteRTLoadCommand = RegExp(
    r'^\s+(.+?libCLiteRTLM_mac\.dylib)\s+\(',
    multiLine: true,
  );
  final RegExpMatch? loadCommand = liteRTLoadCommand.firstMatch(
    linkedLibraries.stdout.toString(),
  );
  if (linkedLibraries.exitCode != 0 || loadCommand == null) {
    _fail('main executable does not link LiteRT-LM.');
  }

  final ProcessResult loadCommands = await Process.run(
    '/usr/bin/otool',
    <String>['-l', executable.path],
  );
  if (loadCommands.exitCode != 0 ||
      !_resolvesToBundledDylib(
        loadCommand.group(1)!,
        loadCommands.stdout.toString(),
        executable,
        dylib,
      )) {
    _fail('LiteRT-LM load path is not resolvable inside app bundle.');
  }

  final ProcessResult signature = await Process.run(
    '/usr/bin/codesign',
    <String>['--verify', '--deep', '--strict', appPath],
  );
  if (signature.exitCode != 0) {
    _fail('app bundle code signature is invalid.');
  }

  final bool launchSmoke =
      arguments.length == 2 && arguments[1] == '--launch-smoke';
  if (launchSmoke) {
    await _verifyLaunchSmoke(executable);
  }

  stdout.writeln(
    launchSmoke
        ? 'LiteRT-LM app bundle launch smoke passed.'
        : 'LiteRT-LM app bundle smoke passed.',
  );
}

Future<void> _verifyLaunchSmoke(File executable) async {
  late final Process process;
  try {
    process = await Process.start(executable.path, const <String>[]);
  } on ProcessException {
    _fail('app could not be launched.');
  }
  process.stdout.drain<void>();
  process.stderr.drain<void>();

  final Object gracePeriodElapsed = Object();
  final Object outcome = await Future.any<Object>(<Future<Object>>[
    process.exitCode.then<Object>((int code) => code),
    Future<Object>.delayed(
      const Duration(seconds: 1),
      () => gracePeriodElapsed,
    ),
  ]);
  if (!identical(outcome, gracePeriodElapsed)) {
    _fail('app exited during launch smoke.');
  }

  process.kill();
  try {
    await process.exitCode.timeout(const Duration(seconds: 1));
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
  }
}

bool _resolvesToBundledDylib(
  String loadPath,
  String loadCommands,
  File executable,
  File dylib,
) {
  final List<String> candidates = <String>[];
  if (loadPath.startsWith('@rpath/')) {
    final String suffix = loadPath.substring('@rpath/'.length);
    final RegExp rpathPattern = RegExp(
      r'cmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset',
      multiLine: true,
    );
    for (final RegExpMatch match in rpathPattern.allMatches(loadCommands)) {
      final String? expanded = _expandLoaderPath(
        match.group(1)!,
        executable.parent.path,
      );
      if (expanded != null) {
        candidates.add('$expanded/$suffix');
      }
    }
  } else {
    final String? expanded = _expandLoaderPath(
      loadPath,
      executable.parent.path,
    );
    if (expanded != null) {
      candidates.add(expanded);
    }
  }

  final String expected = dylib.resolveSymbolicLinksSync();
  for (final String candidate in candidates) {
    final File file = File(candidate);
    if (file.existsSync() && file.resolveSymbolicLinksSync() == expected) {
      return true;
    }
  }
  return false;
}

String? _expandLoaderPath(String path, String executableDirectory) {
  if (path == '@executable_path' || path == '@loader_path') {
    return executableDirectory;
  }
  if (path.startsWith('@executable_path/')) {
    return '$executableDirectory/${path.substring('@executable_path/'.length)}';
  }
  if (path.startsWith('@loader_path/')) {
    return '$executableDirectory/${path.substring('@loader_path/'.length)}';
  }
  if (path.startsWith('/')) {
    return path;
  }
  return null;
}

Never _fail(String message, {int exitCode = 1}) {
  stderr.writeln('bundle-smoke-error: $message');
  exit(exitCode);
}
