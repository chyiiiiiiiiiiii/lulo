import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/settings/settings_sheet.dart';
import 'package:local_agent_macos/features/sidecar/sidecar_health.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

void main() {
  Widget section(Set<int> listening) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ListView(
        children: <Widget>[
          SidecarSection(
            probe: SidecarHealthProbe(
              connect: (int port, Duration timeout) async {
                if (!listening.contains(port)) {
                  throw const SocketException('connection refused');
                }
              },
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> show(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(widget);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a silent agent says which helper is missing', (
    WidgetTester tester,
  ) async {
    // Without the voice sidecar the agent hears, thinks, writes, and stays
    // quiet — `architecture.md` describes the skipped sentence as designed,
    // and until now nothing on screen said why.
    await show(tester, section(<int>{Sidecar.ears.port}));

    expect(find.textContaining('voice is not running'), findsOneWidget);
    expect(
      find.textContaining('cannot start them for you'),
      findsOneWidget,
      reason: 'the sandbox forbids spawning, so it must not promise a fix',
    );
  });

  testWidgets('both being down is reported at once', (
    WidgetTester tester,
  ) async {
    // Otherwise the user fixes one and discovers the other.
    await show(tester, section(<int>{}));

    expect(find.textContaining('voice is not running'), findsOneWidget);
    expect(find.textContaining('transcriber is not running'), findsOneWidget);
  });

  testWidgets('a healthy machine says so without alarming anyone', (
    WidgetTester tester,
  ) async {
    await show(tester, section(<int>{Sidecar.voice.port, Sidecar.ears.port}));

    expect(find.text('Both are answering.'), findsOneWidget);
    expect(find.textContaining('not running'), findsNothing);
  });

  testWidgets('nothing is drawn before the answer is in', (
    WidgetTester tester,
  ) async {
    // Guessing would show a warning and then take it back, which reads worse
    // than a beat of nothing.
    await tester.pumpWidget(section(<int>{}));

    expect(find.byKey(const Key('setting-sidecars')), findsNothing);
  });

  testWidgets('it can be asked again after the user starts something', (
    WidgetTester tester,
  ) async {
    // A connection proves something is listening, not that it is well, and
    // the answer goes stale the moment a sidecar dies or is started. Without
    // this the section could sit reading "both are answering" directly above
    // a transcription that had just failed.
    final Set<int> listening = <int>{};
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              SidecarSection(
                probe: SidecarHealthProbe(
                  connect: (int port, Duration timeout) async {
                    if (!listening.contains(port)) {
                      throw const SocketException('connection refused');
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('voice is not running'), findsOneWidget);

    listening.addAll(<int>[Sidecar.voice.port, Sidecar.ears.port]);
    await tester.tap(find.byKey(const Key('setting-sidecars-recheck')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Both are answering.'), findsOneWidget);
  });
}
