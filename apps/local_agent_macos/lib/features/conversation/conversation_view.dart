import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../presence/agent_presence_controller.dart';
import '../presence/agent_presence_header.dart';
import 'conversation_view_model.dart';
import 'widgets/conversation_composer.dart';
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
    this.buildObserver,
    super.key,
  });

  /// Creates the ViewModel owned by this view.
  final ConversationViewModel Function() viewModelFactory;

  /// Optional render instrumentation used by tests.
  final ConversationBuildObserver? buildObserver;

  /// Creates the state that owns the feature-scoped ViewModel.
  @override
  State<ConversationView> createState() => _ConversationViewState();
}

final class _ConversationViewState extends State<ConversationView> {
  late final ConversationViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModelFactory();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
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
              completedTurns: _viewModel.completedTurnsListenable,
              activeTurn: _viewModel.activeTurnListenable,
              onPresenceControllerCreated:
                  (AgentPresenceController controller) =>
                      widget.buildObserver?.agentPresenceController =
                          controller,
              onPresenceOrbPaint: () =>
                  widget.buildObserver?.agentPresenceOrbPaints += 1,
              onPresenceSemanticBuild: () =>
                  widget.buildObserver?.agentPresenceSemanticBuilds += 1,
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
    required this.completedTurns,
    required this.activeTurn,
    required this.onPresenceControllerCreated,
    required this.onPresenceOrbPaint,
    required this.onPresenceSemanticBuild,
  });

  final ValueListenable<List<Turn>> completedTurns;
  final ValueListenable<Turn?> activeTurn;
  final AgentPresenceControllerCallback onPresenceControllerCreated;
  final VoidCallback onPresenceOrbPaint;
  final VoidCallback onPresenceSemanticBuild;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
    child: Row(
      children: <Widget>[
        Text('Pocket Agent', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 12),
        AgentPresenceHeader(
          completedTurns: completedTurns,
          activeTurn: activeTurn,
          onControllerCreated: onPresenceControllerCreated,
          onOrbPaint: onPresenceOrbPaint,
          onSemanticBuild: onPresenceSemanticBuild,
        ),
        const Spacer(),
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
  );
}
