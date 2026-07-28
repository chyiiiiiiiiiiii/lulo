import 'dart:async';

import 'package:flutter/material.dart';

import '../features/conversation/conversation_view.dart';
import '../features/presence/agent_presence_controller.dart';
import '../features/presence/agent_presence_orb.dart';
import '../features/presence/desktop_orb_surface.dart';
import '../platform/desktop_host_service.dart';
import 'app_composition.dart';

/// Root application widget that owns the application composition lifecycle.
final class LocalAgentApp extends StatefulWidget {
  /// Creates the local agent application.
  const LocalAgentApp({
    required this.composition,
    this.presenceShaderLoader = loadAgentPresenceShader,
    super.key,
  });

  /// App-scoped dependency owner.
  final AppComposition composition;

  /// Loads the presence shader, with deterministic substitution in tests.
  final AgentPresenceShaderLoader presenceShaderLoader;

  @override
  State<LocalAgentApp> createState() => _LocalAgentAppState();
}

final class _LocalAgentAppState extends State<LocalAgentApp> {
  @override
  void dispose() {
    unawaited(widget.composition.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color seed = Color(0xFF7357E8);
    return MaterialApp(
      title: 'Pocket Agent',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light, seed),
      darkTheme: _theme(Brightness.dark, seed),
      home: _PresentationSwitch(
        composition: widget.composition,
        presenceShaderLoader: widget.presenceShaderLoader,
      ),
    );
  }
}

/// Layout size the conversation keeps while the window is orb-sized.
const Size _collapsedConversationSize = Size(720, 560);

/// Chooses the surface for the window's current form.
///
/// Only this widget rebuilds when the form changes, so switching between the
/// desktop orb and the conversation never rebuilds the conversation itself.
final class _PresentationSwitch extends StatefulWidget {
  const _PresentationSwitch({
    required this.composition,
    required this.presenceShaderLoader,
  });

  final AppComposition composition;
  final AgentPresenceShaderLoader presenceShaderLoader;

  @override
  State<_PresentationSwitch> createState() => _PresentationSwitchState();
}

final class _PresentationSwitchState extends State<_PresentationSwitch> {
  /// Identifies the conversation so it keeps its state when the form changes.
  ///
  /// Collapsing wraps the conversation differently so it can lay out at its own
  /// size inside an orb-sized window. That moves it in the tree, and without a
  /// stable identity Flutter would rebuild it from scratch: the view owns its
  /// ViewModel, so the answer being generated would be cancelled.
  final GlobalKey _conversationKey = GlobalKey();

  /// Identifies the one orb, so that changing form moves it.
  ///
  /// The header and the desktop are different places in the tree, and without a
  /// stable identity Flutter would destroy the orb in the form being left and
  /// build another in the form being entered. That restarts its clock and
  /// reloads its shader on every collapse; with the key the same orb is
  /// reparented and simply keeps running.
  final GlobalKey _orbKey = GlobalKey();

  /// The agent's presence, owned here because both forms show it.
  ///
  /// Created above the conversation rather than inside it: the desktop orb has
  /// to follow the same presence, and a controller owned by the form being
  /// left cannot outlive it.
  final AgentPresenceController _presence = AgentPresenceController();

  @override
  void dispose() {
    _presence.dispose();
    super.dispose();
  }

  /// Builds the one orb at the size and cadence its current host wants.
  ///
  /// The properties change with the form; the orb behind them does not.
  Widget _orb({
    required double extent,
    required bool showLabel,
    required bool continuousMotion,
  }) {
    return AgentPresenceOrb(
      key: _orbKey,
      controller: _presence,
      shaderLoader: widget.presenceShaderLoader,
      extent: extent,
      showLabel: showLabel,
      continuousMotion: continuousMotion,
    );
  }

  /// Builds the conversation, holding the orb only while it is the visible form.
  ///
  /// Exactly one host may hold the orb at a time: the conversation stays
  /// mounted while collapsed, so a header that kept claiming it would collide
  /// with the desktop surface over the same identity.
  Widget _conversation({required bool hostsOrb}) {
    return ConversationView(
      key: _conversationKey,
      viewModelFactory: widget.composition.createConversationViewModel,
      presenceShaderLoader: widget.presenceShaderLoader,
      presenceController: _presence,
      presenceOrb: hostsOrb
          ? _orb(
              extent: AgentPresenceOrb.defaultOrbExtent,
              showLabel: true,
              continuousMotion: false,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final DesktopPresentationHost? host = widget.composition.presentationHost;
    if (host == null) {
      return _conversation(hostsOrb: true);
    }
    return ValueListenableBuilder<DesktopPresentation>(
      valueListenable: host.presentation,
      builder: (BuildContext context, DesktopPresentation mode, Widget? _) {
        final bool expanded = mode == DesktopPresentation.expanded;
        final Widget conversation = _conversation(hostsOrb: expanded);
        return Stack(
          children: <Widget>[
            // The conversation stays mounted in both forms. It owns its
            // ViewModel and tearing it down cancels whatever is being
            // generated, so collapsing to the orb mid-answer would throw the
            // answer away. Offstage keeps it alive without painting it.
            Offstage(
              offstage: !expanded,
              // While collapsed the window is orb-sized, which is far too small
              // for the conversation to lay out in. Giving it its own size
              // keeps that layout stable instead of overflowing every frame.
              child: expanded
                  ? conversation
                  : OverflowBox(
                      alignment: Alignment.topLeft,
                      maxWidth: _collapsedConversationSize.width,
                      maxHeight: _collapsedConversationSize.height,
                      child: SizedBox.fromSize(
                        size: _collapsedConversationSize,
                        child: conversation,
                      ),
                    ),
            ),
            if (!expanded)
              DesktopOrbSurface(
                orb: _orb(
                  extent: desktopOrbExtent,
                  showLabel: false,
                  continuousMotion: true,
                ),
                presenceShaderLoader: widget.presenceShaderLoader,
                onSummon: () =>
                    host.setPresentation(DesktopPresentation.expanded),
                onDragBy: host.moveWindowBy,
              ),
          ],
        );
      },
    );
  }
}

ThemeData _theme(Brightness brightness, Color seed) {
  final ColorScheme colors = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    inputDecorationTheme: InputDecorationTheme(
      fillColor: colors.surfaceContainerHighest,
    ),
  );
}
