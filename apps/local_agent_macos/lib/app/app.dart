import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../features/conversation/conversation_view.dart';
import '../features/presence/agent_presence_controller.dart';
import '../features/presence/agent_presence_orb.dart';
import '../features/presence/desktop_orb_surface.dart';
import '../features/presence/presence_flight.dart';
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

final class _PresentationSwitchState extends State<_PresentationSwitch>
    with SingleTickerProviderStateMixin {
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

  /// Identifies the space the header keeps for the orb while it is away.
  ///
  /// Where the presence lands when the conversation is summoned. Its position
  /// depends on the title beside it, so it is measured rather than assumed.
  final GlobalKey _anchorKey = GlobalKey();

  /// The agent's presence, owned here because both forms show it.
  ///
  /// Created above the conversation rather than inside it: the desktop orb has
  /// to follow the same presence, and a controller owned by the form being
  /// left cannot outlive it.
  final AgentPresenceController _presence = AgentPresenceController();

  /// Drives the presence between the two forms.
  late final AnimationController _flight;

  /// Where the presence starts and ends its journey, in canvas coordinates.
  Rect? _flightFrom;
  Rect? _flightTo;

  /// Whether the presence is on its way to the desktop rather than back.
  bool _collapsing = false;

  /// The canvas covering both forms, held only while the presence is moving.
  DesktopTransitionGeometry? _canvas;

  StreamSubscription<DesktopPresentation>? _requests;

  @override
  void initState() {
    super.initState();
    // Unbounded because the spring passes its destination before settling,
    // and built here rather than lazily: a controller first touched in dispose
    // would ask a deactivated element for its TickerMode.
    _flight = AnimationController.unbounded(vsync: this);
    // The hotkey and the menu bar are native, so collapsing is asked for from
    // there. Without listening the window would simply move and there would be
    // nothing left to draw.
    _requests = widget.composition.presentationHost?.presentationRequests
        .listen(_flyTo);
  }

  @override
  void dispose() {
    unawaited(_requests?.cancel());
    _flight.dispose();
    _presence.dispose();
    super.dispose();
  }

  /// The orb's top-left in the current window, before that window changes.
  Offset? _orbOrigin() {
    final BuildContext? context = _orbKey.currentContext;
    final RenderObject? object = context?.findRenderObject();
    if (object is! RenderBox || !object.hasSize) {
      return null;
    }
    return object.localToGlobal(Offset.zero);
  }

  /// Where the header keeps the orb's place, in canvas coordinates.
  Rect? _anchorRect() {
    final RenderObject? object = _anchorKey.currentContext?.findRenderObject();
    if (object is! RenderBox || !object.hasSize) {
      return null;
    }
    return object.localToGlobal(Offset.zero) & object.size;
  }

  Future<void> _nextFrame() {
    final Completer<void> frame = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!frame.isCompleted) {
        frame.complete();
      }
    });
    return frame.future;
  }

  /// Draws the presence travelling, then lets the window settle into [target].
  Future<void> _flyTo(DesktopPresentation target) async {
    final DesktopPresentationHost? host = widget.composition.presentationHost;
    if (host == null || _canvas != null) {
      return;
    }
    final bool collapsing = target == DesktopPresentation.orb;
    // Measured before the window grows, so it is still in the coordinates of
    // the form being left.
    final Offset? origin = _orbOrigin();

    final DesktopTransitionGeometry canvas = await host
        .beginPresentationTransition(target);
    if (!mounted) {
      return;
    }

    // The form being left occupies a known place on the canvas, so a position
    // measured inside it becomes a canvas position by shifting it there.
    final Rect leaving = collapsing ? canvas.conversation : canvas.orb;
    final double fromExtent = collapsing
        ? AgentPresenceOrb.defaultOrbExtent
        : desktopOrbExtent;
    final Rect from = origin == null
        ? Rect.fromCenter(
            center: leaving.center,
            width: fromExtent,
            height: fromExtent,
          )
        : (origin + leaving.topLeft) & Size.square(fromExtent);
    final Rect to = collapsing
        ? canvas.orb
        : Rect.fromCenter(
            center: canvas.conversation.center,
            width: AgentPresenceOrb.defaultOrbExtent,
            height: AgentPresenceOrb.defaultOrbExtent,
          );

    setState(() {
      _canvas = canvas;
      _flightFrom = from;
      _flightTo = to;
      _collapsing = collapsing;
    });

    if (!collapsing) {
      // The header anchor only has a position once the conversation has been
      // laid out on the canvas, which has not happened yet.
      await _nextFrame();
      if (!mounted) {
        return;
      }
      final Rect? landing = _anchorRect();
      if (landing != null) {
        setState(() => _flightTo = landing);
      }
    }

    // Thrown rather than driven for a fixed time: the presence arrives when
    // its own weight says it does.
    _flight.value = 0;
    await _flight.animateWith(SpringSimulation(presenceFlightSpring, 0, 1, 0));
    if (!mounted) {
      return;
    }
    await host.endPresentationTransition(target);
    if (!mounted) {
      return;
    }
    setState(() {
      _canvas = null;
      _flightFrom = null;
      _flightTo = null;
    });
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
      presenceAnchorKey: _anchorKey,
      presenceOrb: hostsOrb
          ? _orb(
              extent: AgentPresenceOrb.defaultOrbExtent,
              showLabel: true,
              continuousMotion: false,
            )
          : null,
    );
  }

  /// The window while it covers both forms and the presence is travelling.
  ///
  /// The conversation is placed where it actually is on screen rather than
  /// filling the canvas, so it neither reflows nor appears to jump as the
  /// window grows around it. The presence is drawn on top, in flight.
  Widget _flightLayout(DesktopTransitionGeometry canvas) {
    return Stack(
      children: <Widget>[
        Positioned.fromRect(
          rect: canvas.conversation,
          // Held at the size it was, because the canvas is a different shape
          // and laying the conversation out to fill it would be a visible
          // reflow in the middle of the move.
          // The window's own corners are rounded by AppKit, but during a
          // change of form that mask belongs to the canvas covering both
          // shapes, so the conversation has to keep its own.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(windowCornerRadius),
            child: SizedBox.fromSize(
              size: canvas.conversation.size,
              child: AnimatedBuilder(
                animation: _flight,
                builder: (BuildContext context, Widget? conversation) {
                  // The window leaves with the presence rather than after it.
                  // Waiting for the spring to settle left it standing at full
                  // strength while the agent was already resting on the desktop.
                  final double solid = conversationOpacityAt(
                    t: _flight.value,
                    collapsing: _collapsing,
                  );
                  // Never dropped from the tree, even at zero: the header anchor
                  // the presence lands on is measured from this layout, and
                  // Opacity already skips painting when there is nothing to see.
                  return Opacity(
                    opacity: solid,
                    child: Transform.scale(
                      scale: conversationScaleAt(
                        t: _flight.value,
                        collapsing: _collapsing,
                      ),
                      child: conversation,
                    ),
                  );
                },
                child: _conversation(hostsOrb: false),
              ),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _flight,
          builder: (BuildContext context, Widget? _) {
            final Rect rect = _flightRect(canvas);
            return Positioned.fromRect(
              rect: rect,
              // The shader renders at the size it is given rather than being
              // scaled afterwards, so the presence stays crisp all the way.
              child: _orb(
                extent: rect.width,
                showLabel: false,
                continuousMotion: true,
              ),
            );
          },
        ),
      ],
    );
  }

  /// Where the presence is right now, between the two forms.
  Rect _flightRect(DesktopTransitionGeometry canvas) {
    final Rect? from = _flightFrom;
    final Rect? to = _flightTo;
    if (from == null || to == null) {
      return from ?? to ?? Rect.zero;
    }
    return presenceFlightRect(
      from: from,
      to: to,
      t: _flight.value,
      bounds: Offset.zero & canvas.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    final DesktopPresentationHost? host = widget.composition.presentationHost;
    if (host == null) {
      return _conversation(hostsOrb: true);
    }
    final DesktopTransitionGeometry? canvas = _canvas;
    if (canvas != null) {
      return _flightLayout(canvas);
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
