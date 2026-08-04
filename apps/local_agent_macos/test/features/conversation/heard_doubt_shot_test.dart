import 'dart:io';
import 'dart:ui' as ui;

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/widgets/completed_turn.dart';

/// Draws the doubt mark to `build/shots/heard-doubt.png` so a change to it
/// can be looked at rather than only asserted.
///
/// The assertions live next door in `heard_doubt_test.dart`; this exists
/// because a mark whose whole job is to be noticed without shouting is not
/// something `findsOneWidget` can judge. The file is gitignored and
/// rewritten on every run.
void main() {
  setUpAll(() async {
    // `flutter test` ships no fonts, so without these every glyph renders
    // as a box and the image proves only the layout. Both loads are
    // best-effort: a machine missing either still runs the test.
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFont(
      'Arial Unicode',
      File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf'),
    );
    await _loadFont('MaterialIcons', _materialIcons());
  });

  testWidgets('the doubt mark, as it looks', (WidgetTester tester) async {
    Turn spoken(String text, double? confidence) => Turn.voice(
      voiceInput: TranscriptRefinement(
        rawTranscript: text,
        proposedTranscript: null,
        selectedTranscript: text,
        status: TranscriptRefinementStatus.unchanged,
        edits: const <TranscriptEdit>[],
        rejectionReasons: const <TranscriptRejectionReason>[],
        refinerId: 'shot',
        refinerVersion: '1',
        elapsed: Duration.zero,
        heardConfidence: confidence,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          fontFamily: 'Arial Unicode',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B7CFF)),
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: const Key('shot'),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CompletedTurn(turn: spoken('介紹一下台北的天氣', 0.97)),
                  CompletedTurn(turn: spoken('計算怎麼吃比較好', 0.48)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

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
    File(
      '${out.path}/heard-doubt.png',
    ).writeAsBytesSync(bytes.buffer.asUint8List());
  });
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

/// The framework's own icon font, wherever this machine keeps the cache.
///
/// The binary running the test sits inside it at one of two depths — the
/// Dart VM at `cache/dart-sdk/bin/dart`, `flutter_tester` at
/// `cache/artifacts/engine/<host>/` — so walk up until the fonts appear.
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
