import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_agent_macos/features/presence/agent_presence_controller.dart';
import 'package:local_agent_macos/features/presence/agent_presence_orb.dart';
import 'package:local_agent_macos/features/presence/desktop_orb_surface.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

/// What the resting orb actually puts on the desktop, read back from the real
/// shader.
///
/// The desktop is the one place where every pixel the orb does not need is the
/// user's own screen, and a fragment program cannot be reasoned about from its
/// source: what matters is the alpha that survives to the framebuffer. So this
/// runs against the real engine and measures it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The faintest alpha a display can show. Below this the compositor rounds
  /// the pixel away and the desktop shows through untouched.
  const int visibleAlpha = 1;

  /// How finely the square is cut into rings for the reading.
  const int rings = 40;

  testWidgets('the resting orb paints nothing outside its silhouette', (
    WidgetTester tester,
  ) async {
    final AgentPresenceController controller = AgentPresenceController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Center(
          child: RepaintBoundary(
            key: const Key('silhouette-capture'),
            child: AgentPresenceOrb(
              controller: controller,
              extent: desktopOrbExtent,
              showLabel: false,
              continuousMotion: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      find.byKey(const Key('agent-presence-shader-ready')),
      findsOneWidget,
      reason: 'the fallback painter would measure the wrong silhouette',
    );

    final RenderRepaintBoundary boundary = tester.renderObject(
      find.byKey(const Key('silhouette-capture')),
    );
    final ui.Image image = (await tester.runAsync(
      () => boundary.toImage(pixelRatio: 2),
    ))!;
    final ByteData pixels = (await tester.runAsync(
      () async =>
          (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!,
    ))!;
    final int width = image.width;
    final int height = image.height;
    image.dispose();

    // The strongest alpha found in each ring, so one lit wisp counts against
    // the bound rather than being averaged away by the dark pixels beside it.
    final List<int> strongest = List<int>.filled(rings, 0);
    final double centre = width / 2;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int alpha = pixels.getUint8((y * width + x) * 4 + 3);
        if (alpha == 0) {
          continue;
        }
        final double radius =
            math.sqrt(
              math.pow(x + 0.5 - centre, 2) + math.pow(y + 0.5 - centre, 2),
            ) /
            centre;
        final int ring = (radius * rings).floor();
        if (ring < rings && alpha > strongest[ring]) {
          strongest[ring] = alpha;
        }
      }
    }

    final StringBuffer profile = StringBuffer('presence_silhouette_profile');
    for (int ring = 0; ring < rings; ring++) {
      profile.write(' ${(ring / rings).toStringAsFixed(3)}=${strongest[ring]}');
    }
    debugPrint(profile.toString());

    final int firstRingOutside = (agentPresenceSilhouetteFraction * rings)
        .ceil();
    for (int ring = firstRingOutside; ring < rings; ring++) {
      expect(
        strongest[ring],
        lessThan(visibleAlpha),
        reason:
            'the orb still paints at ${(ring / rings).toStringAsFixed(3)} of '
            'its square, past the silhouette the click catcher stops at',
      );
    }
  });
}
