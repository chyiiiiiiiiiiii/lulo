import 'dart:async';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../features/conversation/conversation_storage_service.dart';
import '../features/conversation/conversation_view.dart';
import '../features/conversation/widgets/conversation_history_sheet.dart';
import '../features/model/model_catalog.dart';
import '../features/presence/agent_presence_controller.dart';
import '../features/presence/agent_presence_orb.dart';
import '../features/presence/desktop_orb_surface.dart';
import '../features/presence/presence_flight.dart';
import '../features/settings/app_settings.dart';
import '../features/settings/settings_sheet.dart';
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
      title: 'Lulo',
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
    with TickerProviderStateMixin {
  /// Identifies the conversation so it keeps its state when the form changes.
  ///
  /// Collapsing wraps the conversation differently so it can lay out at its own
  /// size inside an orb-sized window. That moves it in the tree, and without a
  /// stable identity Flutter would rebuild it from scratch: the view owns its
  /// ViewModel, so the answer being generated would be cancelled.
  ///
  /// Replaced only when the user changes conversation: that rebuild is the
  /// point, because the view owns its ViewModel and a new conversation is a
  /// new ViewModel.
  GlobalKey _conversationKey = GlobalKey();

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

  /// Drives the conversation away and back: 0 is present, 1 is gone.
  ///
  /// Deliberately not the flight's clock. The flight cannot start until the
  /// window has been resized and its surface reallocated, and leaving depends
  /// on none of that, so it answers the keystroke straight away and covers
  /// the wait that would otherwise be a still screen.
  late final AnimationController _leaving;

  /// Where the presence starts and ends its journey, in canvas coordinates.
  Rect? _flightFrom;
  Rect? _flightTo;

  /// The canvas covering both forms, held only while the presence is moving.
  DesktopTransitionGeometry? _canvas;

  /// Where each form sits inside the window, which never changes size.
  ///
  /// Both forms are drawn inside one window, so each is placed rather than
  /// filling it. Until this arrives there is nothing to place anything
  /// against, which lasts one round trip at launch.
  DesktopTransitionGeometry? _stage;

  StreamSubscription<DesktopPresentation>? _requests;
  StreamSubscription<void>? _settingsRequests;
  StreamSubscription<DesktopTransitionGeometry>? _geometryChanges;

  /// The user's choices, and whether they are currently being looked at.
  AppSettings _settings = const AppSettings();
  bool _showingSettings = false;

  /// The stored conversations, and whether they are currently being looked at.
  List<ConversationSummary> _conversations = const <ConversationSummary>[];
  bool _showingConversations = false;

  /// Which conversation the view was asked to hold.
  ///
  /// Null with [_startFresh] unset means the most recently spoken-in one,
  /// which is what launch resumes; null with it set means a deliberately new
  /// conversation.
  ConversationId? _openConversation;
  bool _startFresh = false;

  @override
  void initState() {
    super.initState();
    // Unbounded because the spring passes its destination before settling,
    // and built here rather than lazily: a controller first touched in dispose
    // would ask a deactivated element for its TickerMode.
    _flight = AnimationController.unbounded(vsync: this);
    _leaving = AnimationController(
      vsync: this,
      duration: leavingDuration,
      value:
          widget.composition.presentationHost?.presentation.value ==
              DesktopPresentation.orb
          ? 1
          : 0,
    );
    // The hotkey and the menu bar are native, so collapsing is asked for from
    // there. Without listening the window would simply move and there would be
    // nothing left to draw.
    _requests = widget.composition.presentationHost?.presentationRequests
        .listen(_flyTo);
    unawaited(_loadStage());
    final Future<void> settingsLoaded = _loadSettings();
    unawaited(settingsLoaded);
    _settingsRequests = widget.composition.presentationHost?.settingsRequests
        .listen((void _) {
          // Not before the stored settings have arrived: the sheet applies
          // each flip over the settings it can see, and a sheet over the
          // defaults would save defaults-plus-one-flip, silently erasing
          // every stored choice.
          unawaited(
            settingsLoaded.then((void _) {
              if (mounted) {
                setState(() => _showingSettings = true);
              }
            }),
          );
        });
    // The window's frame belongs to the user — resized, zoomed, or taken full
    // screen — and the forms are laid out against it, so the layout follows.
    _geometryChanges = widget.composition.presentationHost?.geometryChanges
        .listen((DesktopTransitionGeometry stage) {
          if (mounted && _canvas == null) {
            setState(() => _stage = stage);
          }
        });
    // The form can also change without having been asked for here: the host
    // settles the window itself when the app does not answer in time. Leaving
    // follows the form as well as the flight, or the conversation is left
    // standing on a desktop that has already collapsed.
    widget.composition.presentationHost?.presentation.addListener(
      _followPresentation,
    );
  }

  void _followPresentation() {
    if (_canvas != null) {
      return;
    }
    final DesktopPresentation? mode =
        widget.composition.presentationHost?.presentation.value;
    _leaving.value = mode == DesktopPresentation.orb ? 1 : 0;
  }

  /// Fetches [entry], then thinks with it as soon as it is whole.
  ///
  /// Asked for by hand, so its completion is the activation the user meant.
  Future<void> _downloadModel(ModelCatalogEntry entry) async {
    final File model;
    try {
      model = await widget.composition.modelDownloads.download(entry);
    } on Object {
      // The manager already stands the row back up as not-installed; the
      // sheet is where the user learns the download did not finish.
      return;
    }
    if (!mounted) {
      return;
    }
    await _changeSettings(_settings.copyWith(modelPath: model.path));
  }

  /// Thinks with the already-installed [entry].
  void _useModel(ModelCatalogEntry entry) {
    final File? model = widget.composition.modelDownloads.installedFileOf(
      entry,
    );
    if (model != null && mounted) {
      unawaited(_changeSettings(_settings.copyWith(modelPath: model.path)));
    }
  }

  /// Reads the store and puts its conversations in front of the user.
  Future<void> _showConversations() async {
    final List<ConversationSummary> conversations = await widget.composition
        .listConversations();
    if (!mounted) {
      return;
    }
    setState(() {
      _conversations = conversations;
      _showingConversations = true;
    });
  }

  /// Puts [conversationId] into the view, in place of what it held.
  void _openStoredConversation(ConversationId conversationId) {
    setState(() {
      _openConversation = conversationId;
      _startFresh = false;
      _conversationKey = GlobalKey();
      _showingConversations = false;
    });
  }

  /// Starts an empty conversation, leaving the stored ones where they are.
  void _startNewConversation() {
    setState(() {
      _openConversation = null;
      _startFresh = true;
      _conversationKey = GlobalKey();
      _showingConversations = false;
    });
  }

  /// Forgets [conversationId]; a view still holding it starts fresh.
  Future<void> _forgetConversation(ConversationId conversationId) async {
    // Launch resumes the most recently spoken-in conversation without naming
    // it here, so "the one being looked at" includes the head of the list the
    // user is deleting from.
    final bool wasOpen =
        conversationId == _openConversation ||
        (_openConversation == null &&
            // A deliberately fresh conversation is unstored: no row in the
            // list can be it, so no deletion should tear it down.
            !_startFresh &&
            _conversations.isNotEmpty &&
            conversationId == _conversations.first.id);
    await widget.composition.deleteConversation(conversationId);
    final List<ConversationSummary> conversations = await widget.composition
        .listConversations();
    if (!mounted) {
      return;
    }
    setState(() {
      _conversations = conversations;
      if (wasOpen) {
        _openConversation = null;
        _startFresh = true;
        _conversationKey = GlobalKey();
      }
    });
  }

  /// Reads the user's choices and puts the window into them.
  Future<void> _loadSettings() async {
    AppSettings settings = await widget.composition.settingsStore.load();
    if (settings.modelPath.trim().isEmpty) {
      // Nothing chosen yet, but the recommended model is already here: think
      // with it rather than greeting the user with the canned preview. A
      // deliberate choice, once made, is never overridden.
      final ModelCatalogEntry? recommended = widget.composition.catalog
          .where((ModelCatalogEntry entry) => entry.recommended)
          .firstOrNull;
      final File? installed = recommended == null
          ? null
          : widget.composition.modelDownloads.installedFileOf(recommended);
      if (installed != null) {
        settings = settings.copyWith(modelPath: installed.path);
        await widget.composition.settingsStore.save(settings);
        await widget.composition.useModel(installed.path);
      }
    }
    if (!mounted) {
      return;
    }
    setState(() => _settings = settings);
    await _applySettings(settings);
    if (settings.openConversationOnLaunch) {
      await widget.composition.presentationHost?.setPresentation(
        DesktopPresentation.expanded,
      );
    }
  }

  /// Hands the choices to the window and writes them down.
  Future<void> _applySettings(AppSettings settings) async {
    await widget.composition.presentationHost?.setWindowBehaviour(
      keepOrbOnTop: settings.keepOrbOnTop,
      followAcrossSpaces: settings.followAcrossSpaces,
    );
  }

  /// Applies a choice as it is made, rather than behind a save button.
  Future<void> _changeSettings(AppSettings settings) async {
    final String wasThinkingWith = _settings.modelPath;
    setState(() => _settings = settings);
    await _applySettings(settings);
    await widget.composition.settingsStore.save(settings);
    if (!mounted) {
      // Torn down while saving: the composition is being disposed with the
      // widget, and asking it to load a model now would only throw.
      return;
    }
    if (settings.modelPath != wasThinkingWith) {
      // Only when it actually changed: loading a model costs seconds and
      // several gigabytes, and every other switch on this sheet would
      // otherwise pay for it.
      await widget.composition.useModel(settings.modelPath);
    }
  }

  Future<void> _loadStage() async {
    final DesktopPresentationHost? host = widget.composition.presentationHost;
    if (host == null) {
      return;
    }
    final DesktopTransitionGeometry stage = await host.presentationGeometry();
    if (!mounted) {
      return;
    }
    setState(() => _stage = stage);
  }

  @override
  void dispose() {
    unawaited(_requests?.cancel());
    unawaited(_settingsRequests?.cancel());
    unawaited(_geometryChanges?.cancel());
    widget.composition.presentationHost?.presentation.removeListener(
      _followPresentation,
    );
    _flight.dispose();
    _leaving.dispose();
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
    // Answered before anything is asked of the host, so the keystroke has a
    // visible effect while the window is still being prepared.
    if (collapsing) {
      unawaited(_leaving.forward());
    }
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
    //
    // Waited on until it is *home*, not until the spring has finished
    // wobbling. Those are far apart, and the window only settles once this
    // returns, so waiting for the wobble left the agent motionless at its
    // destination with nothing happening around it.
    _flight.value = 0;
    final Completer<void> home = Completer<void>();
    void watchForArrival() {
      if (!home.isCompleted && _flight.value >= 1) {
        home.complete();
      }
    }

    _flight.addListener(watchForArrival);
    final TickerFuture settling = _flight.animateWith(
      SpringSimulation(
        presenceFlightSpring,
        0,
        1,
        0,
        tolerance: presenceFlightTolerance,
      ),
    );
    // A spring that somehow never reaches its target must not hang the app.
    unawaited(
      settling.orCancel
          .whenComplete(() {
            if (!home.isCompleted) {
              home.complete();
            }
          })
          .catchError((Object _) {}),
    );
    await home.future;
    _flight.removeListener(watchForArrival);
    // Parked exactly on the destination, which is exactly where the settled
    // window puts it, so nothing is left to jump.
    _flight.stop();
    _flight.value = 1;
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
    if (!collapsing) {
      // Faded in after the window has settled rather than on the canvas: by
      // then the surface is the conversation's own size, so this costs a
      // fraction of what it would have on the canvas covering both forms.
      unawaited(_leaving.reverse());
    }
  }

  /// Builds the one orb at the size and cadence its current host wants.
  ///
  /// The properties change with the form; the orb behind them does not.
  Widget _orb({
    required double extent,
    required bool showLabel,
    bool continuousMotion = false,
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
    return AnimatedBuilder(
      animation: _leaving,
      builder: (BuildContext context, Widget? view) {
        // Never removed from the tree, even when fully gone: the header
        // anchor the presence lands on is measured from this layout, and
        // Opacity already skips painting when there is nothing to see.
        return Opacity(
          key: const Key('conversation-visibility'),
          opacity: leavingOpacityAt(_leaving.value),
          child: Transform.scale(
            scale: leavingScaleAt(_leaving.value),
            // Rounded from inside the shrink rather than around it. Leaving
            // makes the conversation smaller than the space it occupies, so a
            // rounding applied outside is cut at a size the conversation no
            // longer is: it pulls away from its own corners and shows four
            // square ones for as long as the change of form lasts.
            child: ClipRRect(
              key: const Key('conversation-corners'),
              borderRadius: BorderRadius.circular(windowCornerRadius),
              child: view,
            ),
          ),
        );
      },
      child: ConversationView(
        key: _conversationKey,
        viewModelFactory: () => widget.composition.createConversationViewModel(
          conversationId: _openConversation,
          startFresh: _startFresh,
        ),
        onShowHistory: widget.composition.presentationHost == null
            ? null
            : () => unawaited(_showConversations()),
        presenceShaderLoader: widget.presenceShaderLoader,
        presenceController: _presence,
        presenceAnchorKey: _anchorKey,
        presenceOrb: hostsOrb
            ? _orb(
                extent: AgentPresenceOrb.defaultOrbExtent,
                // The orb already says what the agent is doing with its whole
                // body; a caption spelling it out beside the title is noise.
                // Its state stays readable to assistive tech.
                showLabel: false,
                // On the display's own cadence rather than the cheap stepped
                // idle. The stepping was chosen when this was a small ornament
                // nobody looked at; it is 5fps, and at that rate the vapour
                // visibly jerks.
                continuousMotion: true,
              )
            : null,
      ),
    );
  }

  /// Where the presence is right now, between the two forms.
  Rect _flightRect(DesktopTransitionGeometry stage) {
    final Rect? from = _flightFrom;
    final Rect? to = _flightTo;
    if (from == null || to == null) {
      return from ?? to ?? stage.orb;
    }
    return presenceFlightRect(
      from: from,
      to: to,
      t: _flight.value,
      bounds: Offset.zero & stage.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    final DesktopPresentationHost? host = widget.composition.presentationHost;
    if (host == null) {
      return _conversation(hostsOrb: true);
    }
    // The canvas of a change of form and the resting stage are the same
    // rectangle now that the window keeps one size, so one layout serves both.
    final DesktopTransitionGeometry? stage = _canvas ?? _stage;
    if (stage == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<DesktopPresentation>(
      valueListenable: host.presentation,
      builder: (BuildContext context, DesktopPresentation mode, Widget? _) {
        final bool expanded = mode == DesktopPresentation.expanded;
        final bool travelling = _canvas != null;
        return Stack(
          children: <Widget>[
            Positioned.fromRect(
              rect: stage.conversation,
              // The window's own corners are rounded by AppKit, but that mask
              // belongs to the whole stage, so the conversation drawn inside
              // it keeps its own.
              child: ClipRRect(
                borderRadius: BorderRadius.circular(windowCornerRadius),
                child: SizedBox.fromSize(
                  size: stage.conversation.size,
                  child: Stack(
                    children: <Widget>[
                      _conversation(hostsOrb: expanded && !travelling),
                      // Over the conversation rather than in a window of its
                      // own: the window is the stage and resizing it is what
                      // this app cannot afford to do.
                      if (_showingConversations && expanded && !travelling)
                        ConversationHistorySheet(
                          conversations: _conversations,
                          onOpen: _openStoredConversation,
                          onNew: _startNewConversation,
                          onDelete: (ConversationId conversationId) =>
                              unawaited(_forgetConversation(conversationId)),
                          onClose: () =>
                              setState(() => _showingConversations = false),
                        ),
                      if (_showingSettings && expanded && !travelling)
                        SettingsSheet(
                          settings: _settings,
                          onChanged: (AppSettings settings) =>
                              unawaited(_changeSettings(settings)),
                          onChooseModel: () async =>
                              await host.chooseModelFile(),
                          onClose: () =>
                              setState(() => _showingSettings = false),
                          modelDownloads: widget.composition.modelDownloads,
                          catalog: widget.composition.catalog,
                          onDownloadModel: (ModelCatalogEntry entry) =>
                              unawaited(_downloadModel(entry)),
                          onUseModel: _useModel,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (travelling)
              AnimatedBuilder(
                animation: _flight,
                builder: (BuildContext context, Widget? _) {
                  final Rect rect = _flightRect(stage);
                  return Positioned.fromRect(
                    rect: rect,
                    // Rendered at the size it is passing through rather than
                    // scaled, so the shader stays crisp all the way.
                    child: _orb(
                      extent: rect.width,
                      showLabel: false,
                      continuousMotion: true,
                    ),
                  );
                },
              )
            else if (!expanded)
              Positioned.fromRect(
                rect: stage.orb,
                child: DesktopOrbSurface(
                  orb: _orb(extent: desktopOrbExtent, showLabel: false),
                  presenceShaderLoader: widget.presenceShaderLoader,
                  onSummon: () =>
                      host.setPresentation(DesktopPresentation.expanded),
                  onDragBy: host.moveWindowBy,
                ),
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
