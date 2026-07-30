import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_agent_macos/app/app.dart';
import 'package:local_agent_macos/app/bootstrap.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS renderer exports the loaded presence boundary at DPR 2', (
    WidgetTester tester,
  ) async {
    final composition = createAppComposition(inferenceRuntime: 'fake');
    await tester.pumpWidget(LocalAgentApp(composition: composition));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const Key('agent-presence-shader-ready')),
      findsOneWidget,
    );
    final RenderRepaintBoundary boundary = tester.renderObject(
      find.byKey(const Key('agent-presence-repaint-boundary')),
    );
    final ui.Image image = (await tester.runAsync(
      () => boundary.toImage(pixelRatio: 2),
    ))!;
    expect(image.width, greaterThanOrEqualTo(112));
    expect(image.height, greaterThanOrEqualTo(112));
    final ByteData png = (await tester.runAsync(
      () async => (await image.toByteData(format: ui.ImageByteFormat.png))!,
    ))!;
    image.dispose();

    final File output = File(
      '${Directory.systemTemp.path}/task-5-macos-renderer-dpr2.png',
    );
    output.writeAsBytesSync(png.buffer.asUint8List(), flush: true);
    expect(output.lengthSync(), greaterThan(0));
    debugPrint('presence_renderer_capture=${output.path}');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
