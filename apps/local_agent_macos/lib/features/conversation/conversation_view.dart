import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../platform/desktop_host_service.dart';
import '../presence/agent_presence_controller.dart';
import '../presence/agent_presence_header.dart';
import '../presence/agent_presence_orb.dart';
import '../transcript_refiner/transcript_shadow_coordinator.dart';
import '../voice/voice_conversation_controller.dart';
import '../voice/voice_service.dart';
import '../voice/voice_turn_hud.dart';
import '../voice/voice_turn_log.dart';
import 'conversation_view_model.dart';
import 'widgets/conversation_composer.dart';
import 'widgets/conversation_content_column.dart';
import 'widgets/conversation_list.dart';

/// How much of the surface colour tints the frosted glass under it.
///
/// The desktop behind the window is blurred by the native backdrop; this is
/// the coverage that keeps the words readable over it while the blur still
/// shows through. 0.72 was tried first and swallowed the glass — the
/// material carries a dark tint of its own, so the two stack.
const double conversationSurfaceOpacity = 0.5;

/// Optional build instrumentation used by rendering-isolation tests.
final class ConversationBuildObserver {
  /// Number of top-level chrome builds.
  int chromeBuilds = 0;

  /// Number of conversation-list builds.
  int conversationListBuilds = 0;

  /// Number of completed-turn list builds.
  int completedTurnsBuilds = 0;

  /// Number of active streaming-turn builds.
  int activeStreamingTurnBuilds = 0;

  /// Number of composer builds.
  int composerBuilds = 0;

  /// Reserved count for model-status builds.
  int modelStatusBuilds = 0;

  /// Number of presence-orb paints.
  int agentPresenceOrbPaints = 0;

  /// Number of narrow presence semantic builds.
  int agentPresenceSemanticBuilds = 0;

  /// Feature-local controller exposed only to rendering-isolation tests.
  AgentPresenceController? agentPresenceController;

  /// Resets all counters after the initial layout is established.
  void reset() {
    chromeBuilds = 0;
    conversationListBuilds = 0;
    completedTurnsBuilds = 0;
    activeStreamingTurnBuilds = 0;
    composerBuilds = 0;
    modelStatusBuilds = 0;
    agentPresenceOrbPaints = 0;
    agentPresenceSemanticBuilds = 0;
  }
}

/// The one view that owns one feature-scoped [ConversationViewModel].
final class ConversationView extends StatefulWidget {
  /// Creates a conversation view with a feature-scoped ViewModel factory.
  const ConversationView({
    required this.viewModelFactory,
    this.onShowHistory,
    this.modelLoading,
    this.voiceService,
    this.transcriptRefiner,
    this.transcriptShadow,
    this.protectedVocabulary,
    this.misheard,
    this.floorControl,
    this.unfinishedEndings,
    this.conversationLanguage,
    this.buildObserver,
    this.composerSeed,
    this.presenceShaderLoader = loadAgentPresenceShader,
    this.onPresenceController,
    this.presenceController,
    this.presenceOrb,
    this.presenceAnchorKey,
    this.showVoiceEvidence = false,
    this.liveConversationToggle = false,
    this.voiceRequests,
    this.orbActionRequests,
    this.voiceEngaged,
    this.screenLook,
    super.key,
  });

  /// Takes the invited look at the screen, or null where no screen exists
  /// behind the surface — which hides the button entirely.
  final Future<DesktopScreenLook> Function()? screenLook;

  /// Bumped when something outside this view asks it to start listening.
  ///
  /// The status-bar menu offers it while the window is away, which is most of
  /// the time for a resident agent.
  final ValueListenable<int>? voiceRequests;

  /// What was last asked of the agent from the strip under its resting orb.
  ///
  /// Carried with a sequence number so that pressing the same button twice
  /// arrives twice. The microphone, the screen look and the stop all live
  /// here — this view is the only thing that knows whether an ear is already
  /// open or an answer still running — so the request travels in rather than
  /// the state travelling out.
  final ValueListenable<(OrbActionKind, int)?>? orbActionRequests;

  /// Set to whether the microphone is currently open, for whoever is drawing
  /// a control that has to show it — the strip under the resting orb.
  final ValueNotifier<bool>? voiceEngaged;

  /// Whether to show why the agent took or yielded the floor.
  ///
  /// An instrument for tuning turn-taking rather than a feature: the rules
  /// are judgement calls, and one that cannot be seen firing is
  /// indistinguishable from a bug.
  final bool showVoiceEvidence;

  /// Whether the chrome offers the always-on microphone toggle.
  ///
  /// Off by default: holding to talk is the product's answer, and a toggle
  /// that opens an always-listening, audio-ducking session is offered only
  /// after the user asked for it in Settings.
  final bool liveConversationToggle;

  /// Presence to project conversation state into, or null to own one.
  final AgentPresenceController? presenceController;

  /// The orb to place in the header, or null to let the header build one.
  ///
  /// The app supplies the single orb it moves between here and the desktop, so
  /// that collapsing relocates the presence rather than rebuilding it.
  final Widget? presenceOrb;

  /// Identifies the space the header keeps for the orb while it is elsewhere.
  final Key? presenceAnchorKey;

  /// Creates the ViewModel owned by this view.
  final ConversationViewModel Function() viewModelFactory;

  /// Called when the user asks for the list of conversations.
  ///
  /// Null hides the button: surfaces with no store behind them have no list
  /// to show.
  final VoidCallback? onShowHistory;

  /// Whether the local model is still loading.
  ///
  /// Loading it takes seconds — measured on the real one at 3.7-8.5 s against
  /// 1.5 s for the first answer once it is in memory — and `warmUp()` starts
  /// it at launch, so a question asked in the first few seconds waits for it
  /// with nothing on screen to say why. That wait is indistinguishable from a
  /// hang. Null where nothing knows: the tests that do not care, and the
  /// preview runtime that has no model to load.
  final ValueListenable<bool>? modelLoading;

  /// The ears and mouth behind the microphone button.
  ///
  /// Null hides the button: surfaces with no voice behind them cannot
  /// listen.
  final VoiceService? voiceService;

  /// Final-transcript refiner supplied by the app composition.
  final TranscriptRefiner? transcriptRefiner;

  /// Optional developer-only transcript shadow coordinator.
  final TranscriptShadowCoordinator? transcriptShadow;

  /// Latest vocabulary tokens protected during refinement.
  final List<String> Function()? protectedVocabulary;

  /// Corrections the user has taught the recogniser, or null on a surface
  /// with no profile behind it.
  final List<MisheardWord> Function()? misheard;

  /// Text handed in from outside the window — a selection sent from another
  /// app's Services menu — or null on a surface where nothing does.
  final Stream<String>? composerSeed;

  /// Who has the floor, or null to use the built-in policy.
  final FloorControl Function()? floorControl;

  /// The user's own ways of leaving a sentence unfinished, or null for none.
  final List<String> Function()? unfinishedEndings;

  /// Which language this conversation is spoken in, or null for English.
  ///
  /// Read when the microphone opens rather than captured, because the user
  /// may change it between sessions and the recogniser is opened afresh
  /// each time.
  final AgentLanguage Function()? conversationLanguage;

  /// Optional render instrumentation used by tests.
  final ConversationBuildObserver? buildObserver;

  /// Loads the presence shader, with deterministic substitution in tests.
  final AgentPresenceShaderLoader presenceShaderLoader;

  /// Reports the presence controller this view drives from conversation state.
  ///
  /// The desktop presence shows the same agent, so it follows this controller
  /// rather than projecting the conversation a second time.
  final ValueChanged<AgentPresenceController>? onPresenceController;

  /// Creates the state that owns the feature-scoped ViewModel.
  @override
  State<ConversationView> createState() => _ConversationViewState();
}

final class _ConversationViewState extends State<ConversationView> {
  late final ConversationViewModel _viewModel;
  VoiceConversationController? _voice;

  /// Why the agent took or yielded the floor, recorded whether or not the
  /// panel is showing.
  ///
  /// Always kept, because a user who turns the panel on has just watched
  /// the thing they wanted explained — showing them an empty list would be
  /// answering "why did it do that?" with "ask it again".
  final VoiceTurnLog _turnLog = VoiceTurnLog();

  /// The measured height of the glass floating over the list's tail.
  double _bottomInset = 0;

  /// Where being cut off mid-thought is counted, so the words this speaker
  /// trails off on can be suggested rather than guessed.
  ///
  /// Seeded with what the profile already lists, read live, so a suggestion
  /// the user has just acted on stops being made.
  late final CutOffLedger _cutOffs = CutOffLedger(
    alreadyListed: widget.unfinishedEndings ?? _emptyProtectedVocabulary,
  );

  /// Whether the user is holding to talk, narrowed for the presence: the
  /// orb leans into listening while this is true, in either form.
  final ValueNotifier<bool> _holdingToTalk = ValueNotifier<bool>(false);

  /// Whether the agent is audibly speaking. The conversation's text can be
  /// fully written minutes before the voice finishes reading it, and the
  /// presence must follow the mouth, not the pen.
  final ValueNotifier<bool> _agentSpeaking = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModelFactory();
    final VoiceService? voiceService = widget.voiceService;
    if (voiceService != null) {
      final VoiceConversationController voice = VoiceConversationController(
        voice: voiceService,
        conversation: _viewModel,
        transcriptRefiner:
            widget.transcriptRefiner ?? const DeterministicTranscriptRefiner(),
        transcriptShadow: widget.transcriptShadow,
        protectedVocabulary:
            widget.protectedVocabulary ?? _emptyProtectedVocabulary,
        misheard: widget.misheard ?? _nothingMisheard,
        turnLog: _turnLog,
        floorControl: widget.floorControl ?? _builtInFloorControl,
        unfinishedEndings:
            widget.unfinishedEndings ?? _emptyProtectedVocabulary,
        cutOffs: _cutOffs,
        language: widget.conversationLanguage ?? _englishConversation,
      );
      _voice = voice;
      voice.addListener(_reflectVoice);
      widget.voiceRequests?.addListener(_startListeningOnRequest);
    }
    widget.orbActionRequests?.addListener(_answerTheOrb);
  }

  void _reflectVoice() {
    _holdingToTalk.value = _voice?.holdingToTalk ?? false;
    _agentSpeaking.value = _voice?.speaking ?? false;
    widget.voiceEngaged?.value = _voice?.enabled ?? false;
  }

  /// Does what the button under the resting orb asked for.
  void _answerTheOrb() {
    final (OrbActionKind, int)? request = widget.orbActionRequests?.value;
    if (request == null) {
      return;
    }
    switch (request.$1) {
      case OrbActionKind.talk:
        unawaited(_toggleVoice());
      case OrbActionKind.look:
        if (widget.screenLook != null) {
          unawaited(_lookAtScreen(''));
        }
      case OrbActionKind.stop:
        unawaited(_stopEverything());
    }
  }

  /// Ends the answer, whichever half of it is still running.
  ///
  /// Both halves, because they are not the same one: the words can be
  /// finished minutes before the voice has read them, and a stop that only
  /// cancelled the generation would leave the agent talking.
  Future<void> _stopEverything() async {
    await widget.voiceService?.stopSpeaking();
    await _viewModel.stop();
  }

  /// Takes the invited look and asks about it, or says why it could not.
  ///
  /// The default question exists because a look with an empty field is
  /// still a question — "what am I looking at" — and demanding words first
  /// would turn one click into three.
  Future<void> _lookAtScreen(String text) async {
    final DesktopScreenLook look = await widget.screenLook!();
    if (!mounted) {
      return;
    }
    final AppLocalizations words = AppLocalizations.of(context);
    switch (look.status) {
      case DesktopScreenLookStatus.captured:
        await _viewModel.submit(
          text.isEmpty ? words.lookDefaultPrompt : text,
          imagePath: look.path,
        );
      case DesktopScreenLookStatus.denied:
        // The one state the user can fix, so the notice says where.
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(words.lookDeniedNotice)));
      case DesktopScreenLookStatus.unavailable:
      case DesktopScreenLookStatus.failed:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(words.lookFailedNotice)));
    }
  }

  @override
  void dispose() {
    _voice?.removeListener(_reflectVoice);
    _voice?.dispose();
    _turnLog.dispose();
    _holdingToTalk.dispose();
    _agentSpeaking.dispose();
    widget.voiceRequests?.removeListener(_startListeningOnRequest);
    widget.orbActionRequests?.removeListener(_answerTheOrb);
    _viewModel.dispose();
    super.dispose();
  }

  /// Opens the microphone because something outside asked, not because the
  /// button was pressed — so an already-open one is left alone rather than
  /// being closed by a request to open it.
  void _startListeningOnRequest() {
    final VoiceConversationController? voice = _voice;
    if (voice == null || voice.enabled) {
      return;
    }
    unawaited(voice.enable());
  }

  Future<void> _toggleVoice() async {
    final VoiceConversationController? voice = _voice;
    if (voice == null) {
      return;
    }
    if (voice.enabled) {
      await voice.disable();
    } else {
      await voice.enable();
    }
  }

  @override
  Widget build(BuildContext context) {
    widget.buildObserver?.chromeBuilds += 1;
    return Scaffold(
      // Not the opaque surface: the window behind this Scaffold is clear and
      // the native side blurs the desktop through it, so this is a tint over
      // glass. Opaque would paint the glass back out; bare glass would leave
      // the words on an unreadable blur.
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: conversationSurfaceOpacity),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _ConversationChrome(
              voice: _voice,
              liveConversationToggle: widget.liveConversationToggle,
              holdingToTalk: _voice == null ? null : _holdingToTalk,
              agentSpeaking: _voice == null ? null : _agentSpeaking,
              onToggleVoice: _toggleVoice,
              onShowHistory: widget.onShowHistory,
              completedTurns: _viewModel.completedTurnsListenable,
              activeTurn: _viewModel.activeTurnListenable,
              presenceController: widget.presenceController,
              presenceOrb: widget.presenceOrb,
              presenceAnchorKey: widget.presenceAnchorKey,
              onPresenceControllerCreated:
                  (AgentPresenceController controller) {
                    widget.buildObserver?.agentPresenceController = controller;
                    widget.onPresenceController?.call(controller);
                  },
              onPresenceOrbPaint: () =>
                  widget.buildObserver?.agentPresenceOrbPaints += 1,
              onPresenceSemanticBuild: () =>
                  widget.buildObserver?.agentPresenceSemanticBuilds += 1,
              presenceShaderLoader: widget.presenceShaderLoader,
            ),
            Expanded(
              // The conversation and the glass over it. The list scrolls
              // beneath the composer — that is what its translucency is for
              // — and takes the overlay's measured height as bottom inset so
              // the last message can always clear the glass.
              child: Stack(
                children: <Widget>[
                  ConversationList(
                    completedTurns: _viewModel.completedTurnsListenable,
                    activeTurn: _viewModel.activeTurnListenable,
                    retryAvailable: _viewModel.canSubmitListenable,
                    bottomInset: _bottomInset,
                    // Straight to the voice, not through the conversation
                    // controller: reading one answer aloud must not require
                    // switching the microphone on, which is what enabling the
                    // controller would do.
                    onSpeak: widget.voiceService == null
                        ? null
                        : (String text) =>
                              unawaited(widget.voiceService!.speak(text)),
                    onRegenerate: () =>
                        unawaited(_viewModel.regenerateLastAnswer()),
                    onRevise: (String text) =>
                        unawaited(_viewModel.reviseLastQuestion(text)),
                    onBuild: () =>
                        widget.buildObserver?.conversationListBuilds += 1,
                    onCompletedTurnsBuild: () =>
                        widget.buildObserver?.completedTurnsBuilds += 1,
                    onActiveTurnBuild: () =>
                        widget.buildObserver?.activeStreamingTurnBuilds += 1,
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _ReportHeight(
                      onHeight: _takeBottomInset,
                      child: Column(
                        key: const Key('conversation-bottom-overlay'),
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (widget.modelLoading != null)
                            _ModelLoadingNotice(loading: widget.modelLoading!),
                          if (_voice != null) _HeardSoFar(voice: _voice!),
                          if (widget.showVoiceEvidence)
                            VoiceTurnHud(log: _turnLog),
                          ConversationComposer(
                            canSubmit: _viewModel.canSubmitListenable,
                            onSubmit: _viewModel.submit,
                            onStop: _viewModel.stop,
                            voice: _voice,
                            onBuild: () =>
                                widget.buildObserver?.composerBuilds += 1,
                            seed: widget.composerSeed,
                            onLook: widget.screenLook == null
                                ? null
                                : (String text) =>
                                      unawaited(_lookAtScreen(text)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Takes the overlay's measured height, rebuilding only when it changes —
  /// which is once at first layout and again when the composer grows a line,
  /// never on a streaming delta.
  void _takeBottomInset(double height) {
    if ((height - _bottomInset).abs() < 0.5) {
      return;
    }
    setState(() => _bottomInset = height);
  }
}

/// Reports its child's laid-out height, after the frame that changed it.
final class _ReportHeight extends StatefulWidget {
  const _ReportHeight({required this.onHeight, required this.child});

  final ValueChanged<double> onHeight;
  final Widget child;

  @override
  State<_ReportHeight> createState() => _ReportHeightState();
}

final class _ReportHeightState extends State<_ReportHeight> {
  double? _reported;

  /// After the frame, because the notification arrives mid-layout and the
  /// size is only trustworthy once layout is done.
  void _scheduleReport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final double? height = context.size?.height;
      if (height == null || _reported == height) {
        return;
      }
      _reported = height;
      widget.onHeight(height);
    });
  }

  @override
  Widget build(BuildContext context) {
    // The first measurement; growth afterwards — the composer gaining a line
    // — arrives as a size-changed notification without this rebuilding.
    _scheduleReport();
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (SizeChangedLayoutNotification _) {
        _scheduleReport();
        return true;
      },
      child: SizeChangedLayoutNotifier(child: widget.child),
    );
  }
}

/// Says the model is still loading, and nothing at all once it is not.
///
/// Deliberately not a spinner over the whole surface: the app is usable while
/// the model loads — the scrollback, the settings and the history are all
/// there — and only an answer has to wait. A question typed now is not
/// refused either; it waits on the same readiness attempt the warm-up
/// started. This explains a wait rather than preventing one.
final class _ModelLoadingNotice extends StatelessWidget {
  const _ModelLoadingNotice({required this.loading});

  final ValueListenable<bool> loading;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: loading,
      builder: (BuildContext context, bool isLoading, Widget? child) {
        if (!isLoading) {
          return const SizedBox.shrink();
        }
        return Padding(
          key: const Key('conversation-model-loading'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).conversationModelLoading,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

List<String> _emptyProtectedVocabulary() => const <String>[];

FloorControl _builtInFloorControl() => FloorControl.standard;

final class _ConversationChrome extends StatelessWidget {
  const _ConversationChrome({
    required this.voice,
    required this.liveConversationToggle,
    required this.holdingToTalk,
    required this.agentSpeaking,
    required this.onToggleVoice,
    required this.onShowHistory,
    required this.completedTurns,
    required this.activeTurn,
    required this.presenceController,
    required this.presenceOrb,
    required this.presenceAnchorKey,
    required this.onPresenceControllerCreated,
    required this.onPresenceOrbPaint,
    required this.onPresenceSemanticBuild,
    required this.presenceShaderLoader,
  });

  final VoiceConversationController? voice;
  final ValueListenable<bool>? holdingToTalk;
  final ValueListenable<bool>? agentSpeaking;
  final VoidCallback onToggleVoice;

  /// Whether the always-on microphone toggle is offered at all.
  final bool liveConversationToggle;
  final VoidCallback? onShowHistory;
  final ValueListenable<List<Turn>> completedTurns;
  final ValueListenable<Turn?> activeTurn;
  final AgentPresenceController? presenceController;
  final Widget? presenceOrb;

  /// Identifies the space the header keeps for the orb while it is elsewhere.
  final Key? presenceAnchorKey;
  final AgentPresenceControllerCallback onPresenceControllerCreated;
  final VoidCallback onPresenceOrbPaint;
  final VoidCallback onPresenceSemanticBuild;
  final AgentPresenceShaderLoader presenceShaderLoader;

  @override
  Widget build(BuildContext context) => Padding(
    // In the shared content column, so the title's leading edge is the
    // composer's leading edge at every window size. The window buttons live
    // on the line above, and the clear space over the title keeps this bar
    // from crowding them.
    padding: const EdgeInsets.fromLTRB(
      conversationContentMargin,
      28,
      conversationContentMargin,
      12,
    ),
    child: ConversationContentColumn(
      child: Row(
        children: <Widget>[
          Text('Lulo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 12),
          AgentPresenceHeader(
            completedTurns: completedTurns,
            activeTurn: activeTurn,
            controller: presenceController,
            orb: presenceOrb,
            anchorKey: presenceAnchorKey,
            holding: holdingToTalk,
            speaking: agentSpeaking,
            onControllerCreated: onPresenceControllerCreated,
            onOrbPaint: onPresenceOrbPaint,
            onSemanticBuild: onPresenceSemanticBuild,
            shaderLoader: presenceShaderLoader,
          ),
          const Spacer(),
          if (voice != null && liveConversationToggle)
            AnimatedBuilder(
              animation: voice!,
              builder: (BuildContext context, Widget? _) => IconButton(
                key: const Key('conversation-voice-button'),
                tooltip: voice!.enabled
                    ? AppLocalizations.of(context).voiceTurnOff
                    : AppLocalizations.of(context).voiceTurnOn,
                icon: Icon(
                  voice!.enabled ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: voice!.enabled
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                onPressed: onToggleVoice,
              ),
            ),
          if (onShowHistory != null)
            IconButton(
              key: const Key('conversation-history-button'),
              tooltip: AppLocalizations.of(context).conversationsTooltip,
              icon: const Icon(Icons.history_rounded),
              onPressed: onShowHistory,
            ),
          Semantics(
            label: AppLocalizations.of(context).localModelLabel,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context).localBadge),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// The utterance in progress, floating over the composer while it is heard.
final class _HeardSoFar extends StatelessWidget {
  const _HeardSoFar({required this.voice});

  final VoiceConversationController voice;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: voice,
      builder: (BuildContext context, Widget? _) {
        final String? failure = voice.failure;
        if (failure != null) {
          // The button going dark with no explanation reads as a broken
          // button, not a broken microphone.
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Text(
              AppLocalizations.of(context).voiceStopped(failure),
              key: const Key('conversation-voice-failure'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          );
        }
        final String heard = voice.partialTranscript;
        if (!voice.listening) {
          return const SizedBox.shrink();
        }
        if (heard.isEmpty) {
          // "Nothing happening" and "listening for you" must not look the
          // same: an open microphone says so. Nor may the three silences
          // look the same as each other — in full duplex the microphone
          // never closes, so "Listening…" alone is true while thinking,
          // while talking, and while broken.
          final AppLocalizations words = AppLocalizations.of(context);
          final (IconData icon, String label) = switch (voice.activity) {
            VoiceActivity.listening => (
              Icons.graphic_eq_rounded,
              words.voiceListening,
            ),
            VoiceActivity.thinking => (
              Icons.more_horiz_rounded,
              words.voiceThinking,
            ),
            VoiceActivity.speaking => (
              Icons.volume_up_rounded,
              words.voiceSpeaking,
            ),
            VoiceActivity.paused => (
              Icons.pause_circle_outline_rounded,
              words.voicePaused,
            ),
            VoiceActivity.holding => (Icons.mic_rounded, words.voiceHolding),
            VoiceActivity.shielded => (
              Icons.volume_up_rounded,
              words.voiceAnswering,
            ),
          };
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Row(
              key: const Key('conversation-listening'),
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  icon,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: Text(
            heard,
            key: const Key('conversation-heard-so-far'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      },
    );
  }
}

List<MisheardWord> _nothingMisheard() => const <MisheardWord>[];

/// What language a surface that never said is held in.
AgentLanguage _englishConversation() => AgentLanguage.byDefault;
