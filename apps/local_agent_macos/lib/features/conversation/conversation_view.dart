import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../presence/agent_presence_controller.dart';
import '../presence/agent_presence_header.dart';
import '../presence/agent_presence_orb.dart';
import '../voice/voice_conversation_controller.dart';
import '../voice/voice_service.dart';
import 'conversation_view_model.dart';
import 'widgets/conversation_composer.dart';
import 'widgets/conversation_content_column.dart';
import 'widgets/conversation_list.dart';

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
    this.voiceService,
    this.buildObserver,
    this.presenceShaderLoader = loadAgentPresenceShader,
    this.onPresenceController,
    this.presenceController,
    this.presenceOrb,
    this.presenceAnchorKey,
    super.key,
  });

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

  /// The ears and mouth behind the microphone button.
  ///
  /// Null hides the button: surfaces with no voice behind them cannot
  /// listen.
  final VoiceService? voiceService;

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

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModelFactory();
    final VoiceService? voiceService = widget.voiceService;
    if (voiceService != null) {
      _voice = VoiceConversationController(
        voice: voiceService,
        conversation: _viewModel,
      );
    }
  }

  @override
  void dispose() {
    _voice?.dispose();
    _viewModel.dispose();
    super.dispose();
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _ConversationChrome(
              voice: _voice,
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
              child: ConversationList(
                completedTurns: _viewModel.completedTurnsListenable,
                activeTurn: _viewModel.activeTurnListenable,
                onBuild: () =>
                    widget.buildObserver?.conversationListBuilds += 1,
                onCompletedTurnsBuild: () =>
                    widget.buildObserver?.completedTurnsBuilds += 1,
                onActiveTurnBuild: () =>
                    widget.buildObserver?.activeStreamingTurnBuilds += 1,
              ),
            ),
            if (_voice != null) _HeardSoFar(voice: _voice!),
            ConversationComposer(
              canSubmit: _viewModel.canSubmitListenable,
              onSubmit: _viewModel.submit,
              onStop: _viewModel.stop,
              onBuild: () => widget.buildObserver?.composerBuilds += 1,
            ),
          ],
        ),
      ),
    );
  }
}

final class _ConversationChrome extends StatelessWidget {
  const _ConversationChrome({
    required this.voice,
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
  final VoidCallback onToggleVoice;
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
            onControllerCreated: onPresenceControllerCreated,
            onOrbPaint: onPresenceOrbPaint,
            onSemanticBuild: onPresenceSemanticBuild,
            shaderLoader: presenceShaderLoader,
          ),
          const Spacer(),
          if (voice != null)
            AnimatedBuilder(
              animation: voice!,
              builder: (BuildContext context, Widget? _) => IconButton(
                key: const Key('conversation-voice-button'),
                tooltip: voice!.enabled ? 'Stop listening' : 'Talk to Lulo',
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
              tooltip: 'Conversations',
              icon: const Icon(Icons.history_rounded),
              onPressed: onShowHistory,
            ),
          Semantics(
            label: 'Local model',
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
                const Text('Local'),
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
              'Voice stopped: $failure',
              key: const Key('conversation-voice-failure'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          );
        }
        final String heard = voice.partialTranscript;
        if (!voice.enabled || heard.isEmpty) {
          return const SizedBox.shrink();
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
