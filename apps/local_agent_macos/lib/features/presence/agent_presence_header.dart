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
      if (activeTurn.text.isEmpty) {
        _requestThinking();
      } else {
        _requestSpeaking();
      }
      return;
    }

    final Turn? lastAssistantTurn = widget.completedTurns.value
        .where((Turn turn) => turn.role == TurnRole.assistant)
        .lastOrNull;
    if (lastAssistantTurn?.status == TurnStatus.failed) {
      _controller.dispatch(AgentPresenceEvent.failed, _clock.elapsed);
      return;
    }
    _requestIdle();
  }

  void _requestThinking() {
    switch (_controller.semanticStateListenable.value) {
      case AgentPresenceState.idle:
        _controller.dispatch(
          AgentPresenceEvent.listeningStarted,
          _clock.elapsed,
        );
        _controller.dispatch(
          AgentPresenceEvent.transcriptCommitted,
          _clock.elapsed,
        );
      case AgentPresenceState.listening:
        _controller.dispatch(
          AgentPresenceEvent.transcriptCommitted,
          _clock.elapsed,
        );
      case AgentPresenceState.thinking:
        return;
      case AgentPresenceState.speaking:
        _controller.dispatch(AgentPresenceEvent.speechStopped, _clock.elapsed);
        _requestThinking();
      case AgentPresenceState.working:
        _controller.dispatch(AgentPresenceEvent.workCompleted, _clock.elapsed);
      case AgentPresenceState.error:
        _controller.dispatch(
          AgentPresenceEvent.transcriptCommitted,
          _clock.elapsed,
        );
    }
  }

  void _requestSpeaking() {
    switch (_controller.semanticStateListenable.value) {
      case AgentPresenceState.idle:
      case AgentPresenceState.listening:
        _requestThinking();
        _requestSpeaking();
      case AgentPresenceState.thinking:
        _controller.dispatch(AgentPresenceEvent.speechStarted, _clock.elapsed);
      case AgentPresenceState.speaking:
        return;
      case AgentPresenceState.working:
        _controller.dispatch(AgentPresenceEvent.workCompleted, _clock.elapsed);
        _requestSpeaking();
      case AgentPresenceState.error:
        _controller.dispatch(AgentPresenceEvent.speechStarted, _clock.elapsed);
    }
  }

  void _requestIdle() {
    switch (_controller.semanticStateListenable.value) {
      case AgentPresenceState.idle:
        return;
      case AgentPresenceState.listening:
      case AgentPresenceState.speaking:
        _controller.dispatch(AgentPresenceEvent.speechStopped, _clock.elapsed);
      case AgentPresenceState.thinking:
        _controller.dispatch(AgentPresenceEvent.speechStarted, _clock.elapsed);
        _controller.dispatch(AgentPresenceEvent.speechStopped, _clock.elapsed);
      case AgentPresenceState.working:
        _controller.dispatch(AgentPresenceEvent.workCompleted, _clock.elapsed);
        _requestIdle();
      case AgentPresenceState.error:
        _controller.dispatch(
          AgentPresenceEvent.errorAcknowledged,
          _clock.elapsed,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AgentPresenceOrb(
      controller: _controller,
      onPaint: widget.onOrbPaint,
      onSemanticBuild: widget.onSemanticBuild,
    );
  }
}
