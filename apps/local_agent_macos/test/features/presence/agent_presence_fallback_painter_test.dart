import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/agent_presence_controller.dart';
import 'package:local_agent_macos/features/presence/agent_presence_fallback_painter.dart';
import 'package:local_agent_macos/features/presence/agent_presence_state.dart';
import 'package:local_agent_macos/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('fallback uses a state-selected dark radial gradient', (
    WidgetTester tester,
  ) async {
    final AgentPresenceController controller = AgentPresenceController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));

    final ui.Image idleImage = await _capture(tester);
    addTearDown(idleImage.dispose);
    final int idleCenter = await _pixel(tester, idleImage, 28, 28);
    final int idleInnerRim = await _pixel(tester, idleImage, 10, 28);

    controller.dispatch(
      AgentPresenceEvent.listeningStarted,
      const Duration(milliseconds: 1),
    );
    controller.dispatch(
      AgentPresenceEvent.transcriptCommitted,
      const Duration(milliseconds: 200),
    );
    controller.dispatch(
      AgentPresenceEvent.workStarted,
      const Duration(milliseconds: 400),
    );
    await tester.pump();
    final ui.Image workingImage = await _capture(tester);
    addTearDown(workingImage.dispose);
    final int workingCenter = await _pixel(tester, workingImage, 28, 28);

    expect(idleCenter, isNot(idleInnerRim));
    expect(workingCenter, isNot(idleCenter));
  });
}

Widget _app(AgentPresenceController controller) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: RepaintBoundary(
          key: const Key('fallback-image'),
          child: CustomPaint(
            size: const Size.square(56),
            painter: AgentPresenceFallbackPainter(
              visualInput: controller.visualInputListenable,
              repaint: controller.visualInputListenable,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<ui.Image> _capture(WidgetTester tester) async {
  final RenderRepaintBoundary boundary = tester.renderObject(
    find.byKey(const Key('fallback-image')),
  );
  return (await tester.runAsync(boundary.toImage))!;
}

Future<int> _pixel(WidgetTester tester, ui.Image image, int x, int y) async {
  return (await tester.runAsync(() async {
    final ByteData data = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    return data.getUint32((y * image.width + x) * 4);
  }))!;
}
