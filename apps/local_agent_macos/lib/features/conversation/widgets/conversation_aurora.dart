import 'dart:async';
import 'dart:ui' as ui;

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Loads the aurora's fragment program.
typedef ConversationAuroraShaderLoader = Future<ui.FragmentProgram> Function();

/// The production loader, from the app's bundled shader.
Future<ui.FragmentProgram> loadConversationAuroraShader() =>
    ui.FragmentProgram.fromAsset('shaders/conversation_aurora.frag');

/// Light rising behind the composer while an answer has not begun.
///
/// The wait before the first word runs 1.6 s on a first answer and 5.7 s on
/// a look at the screen. This is ChunUI's `CCAuroraLayer` (MIT,
/// github.com/liseami/ChunUI) under the composer's glass, which blurs it into
/// a glow. It leaves as the first word arrives, because an answer being read
/// is not something to put moving colour behind.
///
/// Two things are taken from ChunUI's own notes on getting it wrong. The
/// shader's clock runs only while the aurora is drawn and is frozen, not
/// reset, when it leaves — a clock read off the wall hands the shader the
/// whole hidden stretch at once, and the sky lurches. And it rises over 1.2 s
/// rather than switching on. Reduce Motion, or a shader that will not load,
/// leaves nothing drawn at all.
final class ConversationAurora extends StatefulWidget {
  /// Shows the aurora whenever [activeTurn] has nothing written yet.
  const ConversationAurora({
    required this.activeTurn,
    this.shaderLoader = loadConversationAuroraShader,
    super.key,
  });

  /// The answer being produced, if any.
  final ValueListenable<Turn?> activeTurn;

  /// Where the fragment program comes from.
  final ConversationAuroraShaderLoader shaderLoader;

  @override
  State<ConversationAurora> createState() => _ConversationAuroraState();
}

final class _ConversationAuroraState extends State<ConversationAurora>
    with TickerProviderStateMixin {
  /// How fast the sky moves against the clock, as ChunUI runs it.
  static const double _speed = 1.6;

  late final AnimationController _presence = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
    reverseDuration: const Duration(milliseconds: 800),
  )..addStatusListener(_presenceChanged);

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _presence,
    curve: Curves.easeInOut,
  );

  late final Ticker _clock = createTicker(_tick);

  /// The shader's clock: seconds of sky shown so far.
  final ValueNotifier<double> _time = ValueNotifier<double>(0);

  /// Where [_time] stood when the clock last stopped.
  double _playedBefore = 0;

  ui.FragmentProgram? _program;
  bool _waiting = false;
  bool _stilled = false;

  @override
  void initState() {
    super.initState();
    widget.activeTurn.addListener(_watch);
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stilled = MediaQuery.disableAnimationsOf(context);
    _watch();
  }

  @override
  void didUpdateWidget(ConversationAurora oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTurn != widget.activeTurn) {
      oldWidget.activeTurn.removeListener(_watch);
      widget.activeTurn.addListener(_watch);
      _watch();
    }
  }

  @override
  void dispose() {
    widget.activeTurn.removeListener(_watch);
    _clock.dispose();
    _presence.dispose();
    _time.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ui.FragmentProgram program = await widget.shaderLoader();
      if (mounted) {
        setState(() => _program = program);
      }
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint(
          'conversation_aurora_unavailable exception_type=${error.runtimeType}',
        );
      }
    }
  }

  /// Reads whether an answer has begun, reacting only when that changes —
  /// never to the tokens themselves.
  void _watch() {
    final Turn? turn = widget.activeTurn.value;
    final bool waiting = turn != null && turn.text.isEmpty && !_stilled;
    if (waiting == _waiting) {
      return;
    }
    _waiting = waiting;
    if (waiting) {
      if (!_clock.isActive) {
        _clock.start();
      }
      _presence.forward();
    } else if (_stilled) {
      _presence.value = 0;
    } else {
      _presence.reverse();
    }
  }

  void _tick(Duration elapsed) {
    _time.value =
        _playedBefore +
        elapsed.inMicroseconds / Duration.microsecondsPerSecond * _speed;
  }

  void _presenceChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      _playedBefore = _time.value;
      _clock.stop();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ui.FragmentProgram? program = _program;
    if (program == null || _presence.isDismissed) {
      return const SizedBox.shrink();
    }
    final ColorScheme colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: FadeTransition(
        opacity: _opacity,
        child: RepaintBoundary(
          child: CustomPaint(
            key: const Key('conversation-aurora'),
            size: Size.infinite,
            painter: ConversationAuroraPainter(
              program: program,
              time: _time,
              // Fixed tones, the same in both schemes: the aurora is light,
              // and a stop that darkens with the dark scheme turns it to
              // smoke. The middle one is the accent at full colour, as
              // ChunUI's is — pastel all the way across, behind grey glass,
              // rendered as fog.
              stops: <Color>[
                colors.primaryFixedDim,
                HSLColor.fromColor(
                  colors.primaryFixedDim,
                ).withLightness(0.66).toColor(),
                colors.tertiaryFixedDim,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One frame of the aurora, drawn from the shader's clock.
final class ConversationAuroraPainter extends CustomPainter {
  /// Paints [program] at [time] across three colour [stops].
  ConversationAuroraPainter({
    required this.program,
    required this.time,
    required this.stops,
  }) : super(repaint: time);

  /// How strong the light is at full presence.
  static const double _strength = 0.75;

  /// The clock wraps once an hour of sky, a jump nobody is watching for,
  /// before single precision starts to show in the noise.
  static const double _timeWrap = 3600;

  /// The aurora's fragment program.
  final ui.FragmentProgram program;

  /// Seconds of sky shown so far; it only moves while the aurora is drawn.
  final ValueListenable<double> time;

  /// The colours across the width, left to right.
  final List<Color> stops;

  @override
  void paint(Canvas canvas, Size size) {
    final ui.FragmentShader shader = program.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time.value % _timeWrap)
      ..setFloat(3, _strength);
    int index = 4;
    for (final Color stop in stops) {
      shader
        ..setFloat(index++, stop.r)
        ..setFloat(index++, stop.g)
        ..setFloat(index++, stop.b);
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(ConversationAuroraPainter oldDelegate) =>
      oldDelegate.program != program ||
      oldDelegate.time != time ||
      !listEquals(oldDelegate.stops, stops);
}
