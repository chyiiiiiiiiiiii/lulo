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

  /// The conversation's presence, once it has been built.
  ///
  /// Held as a listenable so the orb starts following the real agent the moment
  /// the conversation reports it, without rebuilding the conversation itself.
  final ValueNotifier<AgentPresenceController?> _presence =
      ValueNotifier<AgentPresenceController?>(null);

  @override
  void dispose() {
    _presence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DesktopPresentationHost? host = widget.composition.presentationHost;
    final Widget conversation = ConversationView(
      key: _conversationKey,
      viewModelFactory: widget.composition.createConversationViewModel,
      presenceShaderLoader: widget.presenceShaderLoader,
      onPresenceController: (AgentPresenceController controller) {
        _presence.value = controller;
      },
    );
    if (host == null) {
      return conversation;
    }
    return ValueListenableBuilder<DesktopPresentation>(
      valueListenable: host.presentation,
      builder: (BuildContext context, DesktopPresentation mode, Widget? child) {
        final bool expanded = mode == DesktopPresentation.expanded;
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
                  ? child!
                  : OverflowBox(
                      alignment: Alignment.topLeft,
                      maxWidth: _collapsedConversationSize.width,
                      maxHeight: _collapsedConversationSize.height,
                      child: SizedBox.fromSize(
                        size: _collapsedConversationSize,
                        child: child,
                      ),
                    ),
            ),
            if (!expanded)
              ValueListenableBuilder<AgentPresenceController?>(
                valueListenable: _presence,
                builder:
                    (
                      BuildContext context,
                      AgentPresenceController? presence,
                      Widget? _,
                    ) {
                      return DesktopOrbSurface(
                        controller: presence,
                        presenceShaderLoader: widget.presenceShaderLoader,
                        onSummon: () =>
                            host.setPresentation(DesktopPresentation.expanded),
                        onDragBy: host.moveWindowBy,
                      );
                    },
              ),
          ],
        );
      },
      child: conversation,
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
