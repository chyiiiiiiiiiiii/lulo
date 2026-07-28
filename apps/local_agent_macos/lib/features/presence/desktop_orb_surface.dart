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
    this.presenceShaderLoader = loadAgentPresenceShader,
    super.key,
  });

  /// Invoked when the user asks for the conversation.
  final VoidCallback onSummon;

  /// Loads the presence shader, with deterministic substitution in tests.
  final AgentPresenceShaderLoader presenceShaderLoader;

  @override
  State<DesktopOrbSurface> createState() => _DesktopOrbSurfaceState();
}

final class _DesktopOrbSurfaceState extends State<DesktopOrbSurface> {
  late final AgentPresenceController _controller;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    // The controller's initial snapshot is already idle, which is exactly the
    // resting presence this surface should show.
    _controller = AgentPresenceController();
  }

  @override
  void dispose() {
    _controller.dispose();
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
          onTap: widget.onSummon,
          behavior: HitTestBehavior.opaque,
          child: Semantics(
            button: true,
            label: 'Yi, the local agent. Activate to open the conversation.',
            child: Center(
              child: AnimatedScale(
                // A restrained hover response: enough to read as alive without
                // becoming a distraction on the desktop.
                scale: _hovered ? 1.06 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: AgentPresenceOrb(
                  controller: _controller,
                  shaderLoader: widget.presenceShaderLoader,
                  extent: 148,
                  showLabel: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
