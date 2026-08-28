import 'dart:io';
import 'dart:ui' as ui;

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/agent_profile/agent_profile_store.dart';
import 'package:local_agent_macos/features/settings/agent_profile_settings.dart';
import 'package:local_agent_macos/features/settings/settings_sheet.dart';
import 'package:local_agent_macos/features/sidecar/sidecar_health.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';

/// Draws what this session added to `build/shots/`, so it can be looked at
/// rather than only asserted.
///
/// Everything shipped tonight passed a gate that builds and runs tests and
/// never once showed anybody the result. Assertions say a widget is present;
/// they do not say whether a settings sheet now reads as five sections that
/// belong together or as a pile. The files are gitignored and rewritten on
/// every run.
void main() {
  setUpAll(() async {
    // `flutter test` ships no fonts, so without these every glyph is a box
    // and the image proves only the layout. Both loads are best-effort.
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFont(
      'Arial Unicode',
      File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf'),
    );
    await _loadFont('MaterialIcons', _materialIcons());
  });

  // Tall enough for the whole section: in the app these live inside a
  // scrolling list, so an unbounded height here is the harness matching the
  // real surface rather than the widget needing one.
  /// Makes the test surface as tall as the shot needs.
  ///
  /// The default is 800x600, which clipped a settings section that is
  /// several times that — the image came back cropped rather than short.
  void surface(WidgetTester tester, double height) {
    tester.view.physicalSize = Size(760 * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Widget frame(Widget child, {Locale? locale, double height = 1100}) =>
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          fontFamily: 'Arial Unicode',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B7CFF)),
        ),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const Key('shot'),
              child: SizedBox(
                width: 720,
                height: height,
                child: SingleChildScrollView(child: child),
              ),
            ),
          ),
        ),
      );

  testWidgets('the three word lists, as they look', (
    WidgetTester tester,
  ) async {
    // The labels were swapped once already: `vocabulary` was called "words it
    // keeps mishearing", which is what `misheard` does, so a user reading the
    // sheet would have filled in the list measured to change the transcript
    // by not one character.
    surface(tester, 2100);
    await tester.pumpWidget(
      frame(
        locale: const Locale('zh'),
        height: 2100,
        AgentProfileSettings(
          store: InMemoryAgentProfileStore(
            AgentProfile(
              misheard: const <MisheardWord>[
                MisheardWord(heard: 'Dark text', meant: 'Dart test'),
                MisheardWord(heard: '天器', meant: '天氣'),
              ],
              vocabulary: const <String>['Lulo', 'Flutter', 'Gemma'],
              respellings: const <SpokenRespelling>[
                SpokenRespelling(word: '企業', saidAs: '氣業'),
                SpokenRespelling(word: '結構', saidAs: '潔構'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await _shoot(tester, 'settings-words');
  });

  testWidgets('a stopped sidecar, as it looks', (WidgetTester tester) async {
    surface(tester, 260);
    await tester.pumpWidget(
      frame(
        locale: const Locale('zh'),
        height: 260,
        SidecarSection(
          probe: SidecarHealthProbe(
            connect: (int port, Duration timeout) async {
              if (port != Sidecar.ears.port) {
                throw const SocketException('connection refused');
              }
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await _shoot(tester, 'settings-sidecar-stopped');
  });

  testWidgets('the vault section, as it looks', (WidgetTester tester) async {
    surface(tester, 420);
    await tester.pumpWidget(
      frame(
        locale: const Locale('zh'),
        height: 420,
        ObsidianSection(
          enabled: true,
          onEnabledChanged: (bool _) {},
          folder: () async =>
              '/Users/you/Documents/Obsidian Vault/08-ClaudeLog/lulo',
          choose: () async => '',
          forget: () async {},
          lastWrite: ValueNotifier<DesktopVaultStatus?>(
            DesktopVaultStatus.written,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await _shoot(tester, 'settings-vault');
  });

  testWidgets('the vault section when the folder is gone', (
    WidgetTester tester,
  ) async {
    surface(tester, 470);
    await tester.pumpWidget(
      frame(
        locale: const Locale('zh'),
        height: 470,
        ObsidianSection(
          enabled: true,
          onEnabledChanged: (bool _) {},
          folder: () async => '/Volumes/NAS/Obsidian Vault/lulo',
          choose: () async => '',
          forget: () async {},
          lastWrite: ValueNotifier<DesktopVaultStatus?>(
            DesktopVaultStatus.denied,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await _shoot(tester, 'settings-vault-gone');
  });
}

Future<void> _shoot(WidgetTester tester, String name) async {
  final ui.Image image = (await tester.runAsync<ui.Image>(() async {
    final RenderRepaintBoundary boundary =
        tester.renderObject(find.byKey(const Key('shot')))
            as RenderRepaintBoundary;
    return boundary.toImage(pixelRatio: 3);
  }))!;
  final ByteData bytes = (await tester.runAsync<ByteData?>(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  ))!;
  final Directory out = Directory('build/shots')..createSync(recursive: true);
  File('${out.path}/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
}

Future<void> _loadFont(String family, File file) async {
  if (!file.existsSync()) {
    return;
  }
  await (FontLoader(family)..addFont(
        Future<ByteData>.value(file.readAsBytesSync().buffer.asByteData()),
      ))
      .load();
}

File _materialIcons() {
  Directory? at = File(Platform.resolvedExecutable).parent;
  for (int up = 0; up < 6; up++) {
    final File candidate = File(
      '${at!.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (candidate.existsSync()) {
      return candidate;
    }
    at = at.parent;
  }
  return File('');
}
