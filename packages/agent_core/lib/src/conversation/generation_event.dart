import 'conversation_failure.dart';
import 'generation.dart';

/// An event emitted while a generation progresses.
sealed class GenerationEvent {
  /// Creates an event belonging to [generationId].
  const GenerationEvent(this.generationId);

  /// The generation that emitted this event.
  final GenerationId generationId;
}

/// Signals that a [generation] has started.
final class GenerationStarted extends GenerationEvent {
  /// Creates a start event for [generation].
  GenerationStarted(this.generation) : super(generation.id);

  /// The generation that started.
  final Generation generation;
}

/// Supplies an incremental text [delta] from a generation.
final class GenerationDelta extends GenerationEvent {
  /// Creates a delta event for [generationId].
  const GenerationDelta({
    required GenerationId generationId,
    required this.delta,
  }) : super(generationId);

  /// The incremental response text.
  final String delta;
}

/// Signals that a generation completed successfully.
final class GenerationCompleted extends GenerationEvent {
  /// Creates a completion event for [generationId].
  const GenerationCompleted(super.generationId);
}

/// Signals that a generation was cancelled.
final class GenerationCancelled extends GenerationEvent {
  /// Creates a cancellation event for [generationId].
  const GenerationCancelled(super.generationId);
}

/// Signals that a generation ended with a [failure].
final class GenerationFailed extends GenerationEvent {
  /// Creates a failed event for [generationId] and [failure].
  const GenerationFailed({
    required GenerationId generationId,
    required this.failure,
  }) : super(generationId);

  /// The terminal failure.
  final ConversationFailure failure;
}
