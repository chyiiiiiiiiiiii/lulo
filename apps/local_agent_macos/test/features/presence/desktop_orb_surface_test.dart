import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/desktop_orb_surface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the desktop orb paints the agent onto a transparent surface', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size.square(168)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: const Key('orb-surface'),
          child: DesktopOrbSurface(onSummon: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    final RenderRepaintBoundary boundary = tester.renderObject(
      find.byKey(const Key('orb-surface')),
    );
    final ui.Image image = (await tester.runAsync(() => boundary.toImage()))!;
    final ByteData pixels = (await tester.runAsync(
      () async => (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
    ))!;
    image.dispose();

    int painted = 0;
    int opaqueCorners = 0;
    final int width = boundary.size.width.round();
    for (int index = 0; index + 3 < pixels.lengthInBytes; index += 4) {
      final int alpha = pixels.getUint8(index + 3);
      if (alpha > 0) {
        painted++;
      }
      final int pixel = index ~/ 4;
      final bool isCorner =
          (pixel % width < 4 || pixel % width > width - 5) &&
          (pixel ~/ width < 4 || pixel ~/ width > width - 5);
      if (isCorner && alpha > 8) {
        opaqueCorners++;
      }
    }

    expect(
      painted,
      greaterThan(500),
      reason: 'The desktop orb rendered nothing, so the desktop would be bare.',
    );
    // The window behind this surface is transparent and shadowless. If the
    // surface filled its corners the orb would sit inside a visible square.
    expect(
      opaqueCorners,
      0,
      reason: 'The surface painted into its corners, which shows as a box.',
    );
  });

  testWidgets('dragging the orb moves the window without summoning', (
    WidgetTester tester,
  ) async {
    int summons = 0;
    final List<Offset> moves = <Offset>[];
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopOrbSurface(
          onSummon: () => summons += 1,
          onDragBy: moves.add,
        ),
      ),
    );
    await tester.pump();

    final Offset centre = tester.getCenter(find.byType(DesktopOrbSurface));
    await tester.dragFrom(centre, const Offset(60, -25));
    await tester.pump();

    expect(moves, isNotEmpty, reason: 'The drag did not move the window.');
    // The gesture recogniser absorbs the first few points as drag slop before
    // it reports any delta, so the reported movement trails the gesture by that
    // much. What matters is that it follows the same direction and covers most
    // of the distance.
    final Offset total = moves.reduce((Offset a, Offset b) => a + b);
    expect(total.dx, greaterThan(30));
    expect(total.dx, lessThanOrEqualTo(60));
    expect(total.dy, lessThan(0));
    expect(total.dy, greaterThanOrEqualTo(-25));
    expect(
      summons,
      0,
      reason: 'Dragging the orb also opened the conversation.',
    );

    await tester.tap(find.byType(DesktopOrbSurface));
    await tester.pump();
    expect(summons, 1, reason: 'A tap must still open the conversation.');
  });
}
