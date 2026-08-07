import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/agent_presence_controller.dart';
import 'package:local_agent_macos/features/presence/agent_presence_orb.dart';
import 'package:local_agent_macos/features/presence/agent_presence_state.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

/// Hues the shader assigns to each state, in degrees.
const double _speakingHue = 205;
const double _thinkingHue = 250;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the orb repaints in the colour of a controller swapped in', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size.square(200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AgentPresenceController thinking = AgentPresenceController();
    final AgentPresenceController speaking = AgentPresenceController();
    addTearDown(thinking.dispose);
    addTearDown(speaking.dispose);
    thinking.projectConversationState(
      AgentPresenceProjectionState.thinking,
      Duration.zero,
    );
    speaking.projectConversationState(
      AgentPresenceProjectionState.speaking,
      Duration.zero,
    );

    Future<void> pumpWith(AgentPresenceController controller) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ColoredBox(
            color: const Color(0xFF000000),
            child: Center(
              child: RepaintBoundary(
                key: const Key('swap-orb'),
                child: AgentPresenceOrb(
                  controller: controller,
                  extent: 160,
                  showLabel: false,
                  continuousMotion: true,
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
    }

    await pumpWith(thinking);
    expect(
      await _medianHue(tester),
      closeTo(_thinkingHue, 14),
      reason: 'The orb did not start in the thinking colour.',
    );

    // The desktop presence is handed the conversation's controller after it has
    // already been built once, so the colour has to follow the new one.
    await pumpWith(speaking);
    expect(
      await _medianHue(tester),
      closeTo(_speakingHue, 14),
      reason:
          'The orb kept painting from the controller it was first given, so '
          'it showed one state while reporting another.',
    );
  });

  testWidgets('a freshly built orb paints a controller already mid-run', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size.square(200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The conversation has been open for a while, so its presence is stamped
    // far into its own timebase. Collapsing builds a brand new orb whose clock
    // starts at zero, which is the situation that made the desktop orb paint
    // the state the agent was leaving instead of the one it was in.
    const Duration wellIntoTheRun = Duration(minutes: 2);
    final AgentPresenceController controller = AgentPresenceController();
    addTearDown(controller.dispose);
    controller.projectConversationState(
      AgentPresenceProjectionState.thinking,
      wellIntoTheRun,
    );
    controller.projectConversationState(
      AgentPresenceProjectionState.speaking,
      wellIntoTheRun + const Duration(seconds: 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ColoredBox(
          color: const Color(0xFF000000),
          child: Center(
            child: RepaintBoundary(
              key: const Key('swap-orb'),
              child: AgentPresenceOrb(
                controller: controller,
                extent: 160,
                showLabel: false,
                continuousMotion: true,
              ),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);

    expect(
      await _medianHue(tester),
      closeTo(_speakingHue, 14),
      reason:
          'The orb measured blend progress against its own clock, so a '
          'controller already mid-run looked like it had not started.',
    );
  });
}

/// Lets the shader load and the state blend finish.
///
/// The orb measures blend progress with a real stopwatch, and pumping only
/// advances the test's own clock, so real time has to be allowed to pass or the
/// blend never leaves the state it started from.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }
}

/// Median hue of the orb body, in degrees.
Future<double> _medianHue(WidgetTester tester) async {
  final RenderRepaintBoundary boundary = tester.renderObject(
    find.byKey(const Key('swap-orb')),
  );
  final ui.Image image = (await tester.runAsync(() => boundary.toImage()))!;
  final ByteData pixels = (await tester.runAsync(
    () async => (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
  ))!;
  image.dispose();

  final List<double> hues = <double>[];
  for (int index = 0; index + 3 < pixels.lengthInBytes; index += 4) {
    final int r = pixels.getUint8(index);
    final int g = pixels.getUint8(index + 1);
    final int b = pixels.getUint8(index + 2);
    final int a = pixels.getUint8(index + 3);
    if (a < 200 || b < 70 || b < r + 18 || b < g) {
      continue;
    }
    final HSVColor hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
    if (hsv.saturation > 0.15) {
      hues.add(hsv.hue);
    }
  }
  expect(hues, isNotEmpty, reason: 'The orb painted no body pixels.');
  hues.sort();
  return hues[hues.length ~/ 2];
}
