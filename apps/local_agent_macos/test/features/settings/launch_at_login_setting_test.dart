import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/agent_profile/agent_profile_store.dart';
import 'package:local_agent_macos/features/model/model_catalog.dart';
import 'package:local_agent_macos/features/model/model_download_manager.dart';
import 'package:local_agent_macos/features/model/model_file_service.dart';
import 'package:local_agent_macos/features/settings/app_settings.dart';
import 'package:local_agent_macos/features/settings/settings_sheet.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';

void main() {
  final ModelDownloadManager downloads = ModelDownloadManager(
    files: ModelFileService(
      modelsDirectory: Directory('${Directory.systemTemp.path}/lulo-unused'),
      fetch: (Uri url) async => throw StateError('not in this test'),
    ),
  );
  tearDownAll(downloads.dispose);

  /// The sheet over a system that reports [says] and answers [answers].
  ///
  /// [answers] stands in for macOS refusing or deferring what it was asked,
  /// which is the whole reason this switch reads the system rather than
  /// keeping its own copy.
  Widget sheet({
    required DesktopLoginItem says,
    DesktopLoginItem? answers,
    List<bool>? asked,
    bool readThrows = false,
  }) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SettingsSheet(
      agentProfile: InMemoryAgentProfileStore(),
      settings: const AppSettings(),
      onChanged: (AppSettings _) {},
      onChooseModel: () async => '',
      onClose: () {},
      modelDownloads: downloads,
      onDownloadModel: (ModelCatalogEntry _) {},
      onUseModel: (ModelCatalogEntry _) {},
      loginItem: () async {
        if (readThrows) {
          throw StateError('the host is gone');
        }
        return says;
      },
      setLaunchAtLogin: ({required bool enabled}) async {
        asked?.add(enabled);
        return answers ??
            (enabled ? DesktopLoginItem.on : DesktopLoginItem.off);
      },
    ),
  );

  Future<void> show(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(widget);
    // Two pumps: one to mount, one for the system's answer to land.
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('setting-launch-at-login')),
    );
    await tester.pump();
  }

  testWidgets('the switch shows what the system says', (
    WidgetTester tester,
  ) async {
    // The app describes itself as resident and was not there after a restart,
    // because nothing ever asked macOS to start it.
    await show(tester, sheet(says: DesktopLoginItem.on));

    final SwitchListTile tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('setting-launch-at-login')),
    );
    expect(tile.value, isTrue);
  });

  testWidgets('turning it on asks macOS', (WidgetTester tester) async {
    final List<bool> asked = <bool>[];
    await show(tester, sheet(says: DesktopLoginItem.off, asked: asked));

    await tester.tap(find.byKey(const Key('setting-launch-at-login')));
    await tester.pump();

    expect(asked, <bool>[true]);
    final SwitchListTile tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('setting-launch-at-login')),
    );
    expect(tile.value, isTrue);
  });

  testWidgets('a registration macOS is holding says it is not in effect', (
    WidgetTester tester,
  ) async {
    // macOS has it and is waiting for the user to allow it in System
    // Settings. It reads as on because that is what was asked for, and the
    // subtitle is the part that stops it being a false promise.
    await show(tester, sheet(says: DesktopLoginItem.needsApproval));

    final SwitchListTile tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('setting-launch-at-login')),
    );
    expect(tile.value, isTrue);
    expect(find.textContaining('Not in effect yet'), findsOneWidget);
    expect(find.textContaining('System Settings'), findsOneWidget);
  });

  testWidgets('a held registration can still be withdrawn', (
    WidgetTester tester,
  ) async {
    // The trap this replaced: the switch read off, so a tap asked to
    // register a second time. macOS answers that with
    // `kSMErrorAlreadyRegistered`, nothing moved, and there was no way out
    // of the state in either direction.
    final List<bool> asked = <bool>[];
    await show(
      tester,
      sheet(says: DesktopLoginItem.needsApproval, asked: asked),
    );

    await tester.tap(find.byKey(const Key('setting-launch-at-login')));
    await tester.pump();

    expect(asked, <bool>[false], reason: 'the tap withdraws, not re-asks');
  });

  testWidgets('a copy macOS refuses says so instead of flipping back', (
    WidgetTester tester,
  ) async {
    // An app signed ad-hoc from a build directory, which is every build this
    // repository makes. Reading only the status would report `notRegistered`
    // and draw an ordinary off switch, so the user taps it and nothing
    // visibly happens — the exact failure this state exists to name.
    await show(tester, sheet(says: DesktopLoginItem.refused));

    final SwitchListTile tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('setting-launch-at-login')),
    );
    expect(tile.onChanged, isNull);
    expect(find.textContaining('will not accept this copy'), findsOneWidget);
  });

  testWidgets('a macOS too old for this blames the version, not the folder', (
    WidgetTester tester,
  ) async {
    // `SMAppService` is macOS 13 and the deployment target is 12. Moving the
    // app will never help, so it must not be what the user is told to do.
    await show(tester, sheet(says: DesktopLoginItem.unavailable));

    final SwitchListTile tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('setting-launch-at-login')),
    );
    expect(tile.onChanged, isNull);
    expect(find.textContaining('macOS 13'), findsOneWidget);
  });

  testWidgets('a host that cannot be asked says so rather than vanishing', (
    WidgetTester tester,
  ) async {
    // The channel can fail and the host can be disposed. Swallowing that
    // left the row invisible forever with nothing said anywhere.
    await tester.pumpWidget(
      sheet(says: DesktopLoginItem.off, readThrows: true),
    );
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('setting-launch-at-login')),
    );
    await tester.pump();

    final SwitchListTile tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('setting-launch-at-login')),
    );
    expect(tile.onChanged, isNull);
    expect(find.textContaining('Could not ask macOS'), findsOneWidget);
  });

  testWidgets('a surface with no window host shows no switch at all', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsSheet(
          agentProfile: InMemoryAgentProfileStore(),
          settings: const AppSettings(),
          onChanged: (AppSettings _) {},
          onChooseModel: () async => '',
          onClose: () {},
          modelDownloads: downloads,
          onDownloadModel: (ModelCatalogEntry _) {},
          onUseModel: (ModelCatalogEntry _) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('setting-launch-at-login')), findsNothing);
  });
}
