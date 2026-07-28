import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/agent_presence_controller.dart';
import 'package:local_agent_macos/features/presence/agent_presence_orb.dart';
import 'package:local_agent_macos/features/presence/agent_presence_state.dart';

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
      // Let the shader load and the state blend run to completion. The
      // presence eases between states, so sampling early reads a colour part
      // way between the two and says nothing about which controller is driving.
      for (int i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
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
