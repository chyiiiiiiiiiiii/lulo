import 'package:flutter/material.dart';

import 'agent_presence_controller.dart';
import 'agent_presence_orb.dart';

/// The agent's resting presence on the desktop.
///
/// The window behind this surface is transparent and borderless, so the widget
/// paints nothing but the orb. Anything opaque here would show up as a floating
/// rectangle on the desktop.
final class DesktopOrbSurface extends StatefulWidget {
  /// Creates the desktop orb.
  const DesktopOrbSurface({
    required this.onSummon,
    this.onDragBy,
    this.controller,
    this.presenceShaderLoader = loadAgentPresenceShader,
    super.key,
  });

  /// Presence to follow, or null to rest idle.
  ///
  /// Supplying the conversation's controller is what makes the desktop orb
  /// show the same agent: it thinks and speaks while collapsed instead of
  /// sitting still through work it is actually doing.
  final AgentPresenceController? controller;

  /// Invoked when the user asks for the conversation.
  final VoidCallback onSummon;

  /// Invoked as the user drags the orb, with the movement in logical points.
  final ValueChanged<Offset>? onDragBy;

  /// Loads the presence shader, with deterministic substitution in tests.
  final AgentPresenceShaderLoader presenceShaderLoader;

  @override
  State<DesktopOrbSurface> createState() => _DesktopOrbSurfaceState();
}

final class _DesktopOrbSurfaceState extends State<DesktopOrbSurface> {
  AgentPresenceController? _ownedController;
  bool _hovered = false;
  bool _pressed = false;
  bool _dragged = false;

  /// The presence driving the orb, owned here only when none was supplied.
  AgentPresenceController get _controller {
    final AgentPresenceController? supplied = widget.controller;
    if (supplied != null) {
      return supplied;
    }
    // The initial snapshot is already idle, which is the resting presence.
    return _ownedController ??= AgentPresenceController();
  }

  @override
  void dispose() {
    // Only dispose a controller this surface created. The conversation's
    // controller outlives the orb and disposing it would stop the presence.
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No Scaffold and no surface colour: the window behind this is transparent,
    // so anything that fills the bounds would show on the desktop as a box
    // around the orb.
    return Material(
      type: MaterialType.transparency,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () {
            setState(() => _pressed = false);
            widget.onSummon();
          },
          // The orb is draggable, so a drag must not also summon. The window
          // itself cannot be dragged by its background here, because this
          // surface consumes the mouse before AppKit sees it.
          onPanStart: (_) => setState(() {
            _pressed = true;
            _dragged = false;
          }),
          onPanUpdate: (DragUpdateDetails details) {
            _dragged = true;
            widget.onDragBy?.call(details.delta);
          },
          onPanEnd: (_) {
            final bool moved = _dragged;
            setState(() {
              _pressed = false;
              _dragged = false;
            });
            if (!moved) {
              widget.onSummon();
            }
          },
          child: Semantics(
            button: true,
            label:
                'Yi, the local agent. Activate to open the conversation, or '
                'drag to move it.',
            child: Center(
              child: AnimatedScale(
                // A restrained hover response: enough to read as alive without
                // becoming a distraction on the desktop.
                scale: _pressed
                    ? 0.94
                    : _hovered
                    ? 1.06
                    : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: AgentPresenceOrb(
                  controller: _controller,
                  shaderLoader: widget.presenceShaderLoader,
                  extent: 148,
                  showLabel: false,
                  continuousMotion: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
