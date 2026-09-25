import 'package:flutter/material.dart';

/// Brings a turn into the conversation: up from 14pt below while it fades
/// in, on a curve that arrives without overshooting.
///
/// The curve, the distance and the duration are ChunUI's `CCMotion.reveal`
/// (MIT, github.com/liseami/ChunUI). The rise is a paint transform, so the
/// list lays the turn out where it will settle from the first frame and the
/// follow that scrolls to the newest answer never chases a moving target.
final class TurnReveal extends StatefulWidget {
  /// Reveals [child], after [delay], if [play] is set when it first builds.
  const TurnReveal({
    required this.play,
    required this.child,
    this.delay = Duration.zero,
    super.key,
  });

  /// Whether this turn enters with motion or is simply there.
  ///
  /// Read once. A turn that has arrived stays put when the list rebuilds
  /// around it, and one shown as a conversation opens never moves at all.
  final bool play;

  /// How long the turn waits before it starts to enter.
  final Duration delay;

  /// The turn.
  final Widget child;

  @override
  State<TurnReveal> createState() => _TurnRevealState();
}

final class _TurnRevealState extends State<TurnReveal>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 320);
  static const double _rise = 14;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + _duration,
  );

  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      widget.delay.inMicroseconds / (widget.delay + _duration).inMicroseconds,
      1,
      curve: const Cubic(0.22, 0.8, 0.36, 1),
    ),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    if (widget.play && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _progress,
    child: AnimatedBuilder(
      animation: _progress,
      child: widget.child,
      builder: (BuildContext context, Widget? child) => Transform.translate(
        offset: Offset(0, _rise * (1 - _progress.value)),
        child: child,
      ),
    ),
  );
}
