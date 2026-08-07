import 'dart:io';

/// The release build's entitlements have to carry everything the app does.
///
/// The gate builds `--profile`, which signs with `DebugProfile.entitlements`,
/// so nothing else in this repository ever looks at the file a shipped app is
/// actually signed with. A capability missing there fails only in the build
/// nobody tests, and the voice fails silently by design.
void main(List<String> arguments) {
  final File release = File('macos/Runner/Release.entitlements');
  final File debugProfile = File('macos/Runner/DebugProfile.entitlements');
  final String releaseText = release.readAsStringSync();
  final String debugText = debugProfile.readAsStringSync();

  final List<String> missing = <String>[];
  for (final MapEntry<String, String> file in <String, String>{
    'Release.entitlements': releaseText,
    'DebugProfile.entitlements': debugText,
  }.entries) {
    final String? bad = _illegalCommentIn(file.value);
    if (bad != null) {
      missing.add(
        '${file.key} has "--" inside an XML comment ($bad) — XML forbids it, '
        'so a strict parser rejects the whole file even though plutil and '
        'codesign accept it. Both entitlements files are prose-heavy, and a '
        'flag written with two dashes is the way it happens.',
      );
    }
  }

  const Map<String, String> required = <String, String>{
    'com.apple.security.app-sandbox': 'the sandbox is the safety story',
    'com.apple.security.device.audio-input': 'the agent cannot hear',
    'com.apple.security.network.client':
        'the TTS sidecar is reached over http://127.0.0.1:46557, and the '
        'sandbox requires this even for loopback — without it the release '
        'build never speaks, silently',
    'com.apple.security.files.user-selected.read-write':
        'choosing a model and saving an export both need it',
  };
  required.forEach((String key, String why) {
    if (!releaseText.contains('<key>$key</key>')) {
      missing.add('$key — $why');
    }
  });

  // Anything Debug/Profile can do and Release cannot is a capability that
  // works everywhere it is tested and nowhere it ships.
  final RegExp keys = RegExp(r'<key>([^<]+)</key>');
  for (final RegExpMatch match in keys.allMatches(debugText)) {
    final String key = match.group(1)!;
    // Deliberately not required. An entitlement granted on speculation is a
    // widened sandbox bought with nothing.
    const Set<String> onlyForDebugging = <String>{
      // The Dart VM service listens for the debugger; a shipped app serves
      // nothing. It reaches the voice sidecar as a client, which is
      // network.client above.
      'com.apple.security.network.server',
      // Nothing has shown the release build needs it. If the LiteRT-LM GPU
      // path turns out to, that will show up as a release build that cannot
      // load a model — and this list is where to record why it came back.
      'com.apple.security.cs.allow-jit',
    };
    if (onlyForDebugging.contains(key)) {
      continue;
    }
    if (!releaseText.contains('<key>$key</key>')) {
      missing.add('$key — granted in DebugProfile and not in Release');
    }
  }

  if (missing.isEmpty) {
    stdout.writeln('Release entitlements carry every tested capability.');
    return;
  }
  stderr.writeln('Release.entitlements is missing:');
  for (final String line in missing) {
    stderr.writeln('  $line');
  }
  exitCode = 1;
}

/// The offending comment body, or null when every comment is legal XML.
///
/// XML forbids `--` anywhere inside a comment, including at its very end.
/// `plutil` and `codesign` both accept it, so nothing in a normal build says
/// a word — but any strict parser rejects the entire file, and both of these
/// files carry long prose comments explaining why each capability is there.
/// Writing a build flag with its two leading dashes is how it happens.
String? _illegalCommentIn(String text) {
  int at = 0;
  while (true) {
    final int start = text.indexOf('<!--', at);
    if (start < 0) {
      return null;
    }
    final int end = text.indexOf('-->', start + 4);
    if (end < 0) {
      return 'an unterminated comment';
    }
    final String body = text.substring(start + 4, end);
    if (body.contains('--')) {
      final int where = body.indexOf('--');
      final int from = where - 20 < 0 ? 0 : where - 20;
      final int to = where + 20 > body.length ? body.length : where + 20;
      return '...${body.substring(from, to).replaceAll('\n', ' ').trim()}...';
    }
    at = end + 3;
  }
}
