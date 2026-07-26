import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'agent_presence_controller.dart';
import 'agent_presence_orb.dart';
import 'agent_presence_state.dart';

/// Reports the feature-local controller to optional render instrumentation.
typedef AgentPresenceControllerCallback =
    void Function(AgentPresenceController controller);

/// Projects current conversation presentation into the local presence orb.
final class AgentPresenceHeader extends StatefulWidget {
  /// Creates a header that observes only the two narrow conversation values.
  const AgentPresenceHeader({
    required this.completedTurns,
    required this.activeTurn,
    this.onControllerCreated,
    this.onOrbPaint,
    this.onSemanticBuild,
    this.shaderLoader = loadAgentPresenceShader,
    super.key,
  });

  /// Terminal conversation history.
  final ValueListenable<List<Turn>> completedTurns;

  /// Current streaming assistant turn.
  final ValueListenable<Turn?> activeTurn;

  /// Optional controller instrumentation used by isolation tests.
  final AgentPresenceControllerCallback? onControllerCreated;

  /// Optional orb-paint instrumentation used by isolation tests.
  final AgentPresencePaintCallback? onOrbPaint;

  /// Optional semantic-build instrumentation used by isolation tests.
  final VoidCallback? onSemanticBuild;

  /// Loads the presence shader, with deterministic substitution in tests.
  final AgentPresenceShaderLoader shaderLoader;

  @override
  State<AgentPresenceHeader> createState() => _AgentPresenceHeaderState();
}

final class _AgentPresenceHeaderState extends State<AgentPresenceHeader> {
  final AgentPresenceController _controller = AgentPresenceController();
  final Stopwatch _clock = Stopwatch();

  @override
  void initState() {
    super.initState();
    _clock.start();
    widget.completedTurns.addListener(_projectConversation);
    widget.activeTurn.addListener(_projectConversation);
    widget.onControllerCreated?.call(_controller);
    _projectConversation();
  }

  @override
  void didUpdateWidget(AgentPresenceHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.completedTurns != widget.completedTurns) {
      oldWidget.completedTurns.removeListener(_projectConversation);
      widget.completedTurns.addListener(_projectConversation);
    }
    if (oldWidget.activeTurn != widget.activeTurn) {
      oldWidget.activeTurn.removeListener(_projectConversation);
      widget.activeTurn.addListener(_projectConversation);
    }
    _projectConversation();
  }

  @override
  void dispose() {
    widget.completedTurns.removeListener(_projectConversation);
    widget.activeTurn.removeListener(_projectConversation);
    _clock.stop();
    _controller.dispose();
    super.dispose();
  }

  void _projectConversation() {
    final Turn? activeTurn = widget.activeTurn.value;
    if (activeTurn != null) {
      _controller.projectConversationState(
        activeTurn.text.isEmpty
            ? AgentPresenceProjectionState.thinking
            : AgentPresenceProjectionState.speaking,
        _clock.elapsed,
      );
      return;
    }

    final Turn? lastAssistantTurn = widget.completedTurns.value
        .where((Turn turn) => turn.role == TurnRole.assistant)
        .lastOrNull;
    if (lastAssistantTurn?.status == TurnStatus.failed) {
      _controller.projectConversationState(
        AgentPresenceProjectionState.error,
        _clock.elapsed,
      );
      return;
    }
    _controller.projectConversationState(
      AgentPresenceProjectionState.idle,
      _clock.elapsed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AgentPresenceOrb(
      controller: _controller,
      onPaint: widget.onOrbPaint,
      onSemanticBuild: widget.onSemanticBuild,
      shaderLoader: widget.shaderLoader,
    );
  }
}
