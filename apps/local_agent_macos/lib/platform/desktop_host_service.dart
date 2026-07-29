import 'dart:ui' show Offset, Rect, Size;
import 'package:flutter/foundation.dart';

import '../generated/desktop_host_api.g.dart';

/// App-facing contract for the typed macOS host boundary.
abstract interface class DesktopHostService implements DesktopPresentationHost {
  /// Current schema shared by Dart and the generated host bridge.
  static const int schemaVersion = 2;

  /// Events validated and normalized at the platform boundary.
  Stream<DesktopGenerationEvent> get generationEvents;

  /// Negotiates the exact schema and reports native runtime capabilities.
  Future<DesktopRuntimeCapabilities> handshake();

  /// Loads a local model described by [model].
  Future<DesktopModelLoadResult> loadModel(DesktopModelRequest model);

  /// Starts one typed local generation request.
  Future<DesktopGenerationAcknowledgement> startGeneration(
    DesktopGenerationRequest generation,
  );

  /// Requests idempotent cancellation of [generationId].
  Future<DesktopCancellationAcknowledgement> cancelGeneration(
    String generationId,
  );

  /// Resets the bounded native state for [sessionId].
  Future<DesktopOperationCompletion> resetSession(String sessionId);

  /// Releases the currently loaded model.
  Future<DesktopOperationCompletion> unloadModel();

  /// Makes the retained desktop panel visible.
  Future<void> showPanel();

  /// Hides the retained desktop panel without ending the application.
  Future<void> hidePanel();

  /// Toggles visibility of the retained desktop panel.
  Future<void> togglePanel();

  @override
  ValueListenable<DesktopPresentation> get presentation;

  @override
  Future<void> setPresentation(DesktopPresentation mode);

  @override
  Future<void> moveWindowBy(Offset delta);

  /// Releases message handlers and stream resources.
  Future<void> dispose();
}

/// Truthful capabilities returned by the native runtime handshake.
final class DesktopRuntimeCapabilities {
  /// Creates an immutable capability snapshot.
  const DesktopRuntimeCapabilities({
    required this.schemaVersion,
    required this.runtimeName,
    required this.supportsStreaming,
    required this.supportsCancellation,
  });

  /// Exact schema version implemented by the native peer.
  final int schemaVersion;

  /// Stable native runtime implementation name.
  final String runtimeName;

  /// Whether the runtime emits incremental text.
  final bool supportsStreaming;

  /// Whether active generation can be cancelled.
  final bool supportsCancellation;

  @override
  bool operator ==(Object other) {
    return other is DesktopRuntimeCapabilities &&
        schemaVersion == other.schemaVersion &&
        runtimeName == other.runtimeName &&
        supportsStreaming == other.supportsStreaming &&
        supportsCancellation == other.supportsCancellation;
  }

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    runtimeName,
    supportsStreaming,
    supportsCancellation,
  );
}

/// Model identity, location, and bounded context configuration.
final class DesktopModelRequest {
  /// Creates a typed local model request.
  const DesktopModelRequest({
    required this.modelId,
    required this.modelPath,
    required this.contextSize,
  });

  /// Stable product-owned model identifier.
  final String modelId;

  /// Local filesystem path supplied to the native runtime.
  final String modelPath;

  /// Maximum context tokens requested for this load.
  final int contextSize;
}

/// Typed acknowledgement for a model load.
final class DesktopModelLoadResult {
  /// Creates a model load result.
  const DesktopModelLoadResult({required this.modelId, required this.loaded});

  /// Identity of the model addressed by the operation.
  final String modelId;

  /// Whether the model is now loaded.
  final bool loaded;

  @override
  bool operator ==(Object other) {
    return other is DesktopModelLoadResult &&
        modelId == other.modelId &&
        loaded == other.loaded;
  }

  @override
  int get hashCode => Object.hash(modelId, loaded);
}

/// Typed generation payload crossing the native boundary.
final class DesktopGenerationRequest {
  /// Creates an immutable generation request.
  const DesktopGenerationRequest({
    required this.generationId,
    required this.sessionId,
    required this.prompt,
    required this.context,
    required this.temperature,
    required this.topP,
    required this.maxTokens,
    required this.seed,
  });

  /// Stable ID used to correlate acknowledgements and events.
  final String generationId;

  /// Session whose native context should be used.
  final String sessionId;

  /// User prompt passed without logging.
  final String prompt;

  /// Ordered prior context passed without logging.
  final List<String> context;

  /// Sampling temperature.
  final double temperature;

  /// Nucleus sampling probability.
  final double topP;

  /// Maximum number of output tokens.
  final int maxTokens;

  /// Deterministic sampling seed.
  final int seed;
}

/// Typed acknowledgement for generation start.
final class DesktopGenerationAcknowledgement {
  /// Creates a generation acknowledgement.
  const DesktopGenerationAcknowledgement({
    required this.generationId,
    required this.accepted,
  });

  /// Generation addressed by the acknowledgement.
  final String generationId;

  /// Whether the request was accepted.
  final bool accepted;

  @override
  bool operator ==(Object other) {
    return other is DesktopGenerationAcknowledgement &&
        generationId == other.generationId &&
        accepted == other.accepted;
  }

  @override
  int get hashCode => Object.hash(generationId, accepted);
}

/// Typed idempotent cancellation acknowledgement.
final class DesktopCancellationAcknowledgement {
  /// Creates a cancellation acknowledgement.
  const DesktopCancellationAcknowledgement({
    required this.generationId,
    required this.acknowledged,
  });

  /// Generation addressed by the acknowledgement.
  final String generationId;

  /// Whether native state now fences further generation output.
  final bool acknowledged;

  @override
  bool operator ==(Object other) {
    return other is DesktopCancellationAcknowledgement &&
        generationId == other.generationId &&
        acknowledged == other.acknowledged;
  }

  @override
  int get hashCode => Object.hash(generationId, acknowledged);
}

/// Typed completion returned by bounded lifecycle operations.
final class DesktopOperationCompletion {
  /// Creates an operation completion.
  const DesktopOperationCompletion({required this.completed});

  /// Whether the bounded operation completed.
  final bool completed;

  @override
  bool operator ==(Object other) {
    return other is DesktopOperationCompletion && completed == other.completed;
  }

  @override
  int get hashCode => completed.hashCode;
}

/// Stable app failure categories exposed by the desktop host.
enum DesktopHostFailureCode {
  /// The requested local model is not installed.
  modelNotInstalled(
    'modelNotInstalled',
    'The local model is not installed.',
    true,
  ),

  /// The local model could not be loaded.
  modelLoadFailed(
    'modelLoadFailed',
    'The local model could not be loaded.',
    true,
  ),

  /// The selected local runtime is not available.
  runtimeUnavailable(
    'runtimeUnavailable',
    'Local inference is unavailable.',
    true,
  ),

  /// Another generation is already active.
  generationBusy(
    'generationBusy',
    'Another response is already being generated.',
    true,
  ),

  /// Generation ended unsuccessfully.
  generationFailed('generationFailed', 'Local inference failed.', true),

  /// The active operation was cancelled.
  cancelled('cancelled', 'The response was cancelled.', false),

  /// The peer sent an incompatible schema or invalid event order.
  protocolMismatch(
    'protocolMismatch',
    'The desktop host protocol is incompatible.',
    false,
  );

  const DesktopHostFailureCode(
    this.pigeonCode,
    this.userSafeMessage,
    this.isRecoverable,
  );

  /// Stable code serialized across the platform boundary.
  final String pigeonCode;

  /// Stable user-safe message that never includes native diagnostic text.
  final String userSafeMessage;

  /// Whether product behavior can offer retry or corrective action.
  final bool isRecoverable;

  /// Maps a serialized Pigeon [code] to an application failure category.
  static DesktopHostFailureCode fromPigeonCode(String code) {
    return DesktopHostFailureCode.values.firstWhere(
      (DesktopHostFailureCode value) => value.pigeonCode == code,
      orElse: () => DesktopHostFailureCode.protocolMismatch,
    );
  }
}

/// A user-safe failure normalized at the desktop boundary.
final class DesktopHostFailure implements Exception {
  /// Creates a failure whose complete product-visible contract belongs to [code].
  const DesktopHostFailure(this.code);

  /// Stable application failure category.
  final DesktopHostFailureCode code;

  /// Safe diagnostic text without a native stack trace.
  String get message => code.userSafeMessage;

  /// Whether product behavior can offer retry or corrective action.
  bool get isRecoverable => code.isRecoverable;

  @override
  String toString() => 'DesktopHostFailure(${code.pigeonCode}): $message';
}

/// Immutable generation event accepted from the generated host bridge.
final class DesktopGenerationEvent {
  /// Creates a validated event.
  const DesktopGenerationEvent({
    required this.generationId,
    required this.sequence,
    required this.type,
    this.delta,
    this.failureCode,
    this.message,
  });

  /// Stable generation identifier supplied by the native runtime boundary.
  final String generationId;

  /// Strictly increasing sequence within [generationId].
  final int sequence;

  /// Event kind generated by Pigeon.
  final HostGenerationEventType type;

  /// Text payload for delta events.
  final String? delta;

  /// Typed terminal failure, when [type] is failed.
  final DesktopHostFailureCode? failureCode;

  /// Safe terminal diagnostic text.
  final String? message;
}

/// The narrow desktop-window capability the app shell needs.
///
/// Declared separately from [DesktopHostService] so the shell can depend on the
/// window form alone rather than on the whole host surface.
abstract interface class DesktopPresentationHost {
  /// The form the window is currently presented in.
  ValueListenable<DesktopPresentation> get presentation;

  /// Form changes the host is asking the app to draw.
  ///
  /// The hotkey and the menu bar are native, so this is how the app hears
  /// about a change of form early enough to draw the move rather than being
  /// told the window has already moved.
  Stream<DesktopPresentation> get presentationRequests;

  /// Asks the host to present the window in [mode].
  Future<void> setPresentation(DesktopPresentation mode);

  /// Drags the window by [delta], in logical points.
  Future<void> moveWindowBy(Offset delta);

  /// Requests from the menu bar to show the app's settings.
  Stream<void> get settingsRequests;

  /// Asks the user for a model file, returning its path or empty when they
  /// keep what they had.
  Future<String> chooseModelFile();

  /// Applies the user's choices about how the resting orb behaves.
  Future<void> setWindowBehaviour({
    required bool keepOrbOnTop,
    required bool followAcrossSpaces,
  });

  /// Where each form sits inside the window, which never changes size.
  ///
  /// Both forms are drawn inside one window, so each has to be placed rather
  /// than filling it.
  Future<DesktopTransitionGeometry> presentationGeometry();

  /// Grows the window to cover both forms so a move between them can be drawn.
  ///
  /// The window is inert until [endPresentationTransition] settles it.
  Future<DesktopTransitionGeometry> beginPresentationTransition(
    DesktopPresentation target,
  );

  /// Settles the window into [mode] and lets it take the mouse again.
  Future<void> endPresentationTransition(DesktopPresentation mode);
}

/// Where each form sits inside the window that covers both of them.
///
/// Measured from the top-left of that window in logical points, which is the
/// space Flutter lays out in, so these rectangles can be used directly.
@immutable
final class DesktopTransitionGeometry {
  /// Creates the geometry a change of form is drawn inside.
  const DesktopTransitionGeometry({
    required this.size,
    required this.conversation,
    required this.orb,
  });

  /// Size of the window covering both forms.
  final Size size;

  /// Where the conversation sits inside that window.
  final Rect conversation;

  /// Where the resting orb sits inside that window.
  final Rect orb;

  @override
  bool operator ==(Object other) =>
      other is DesktopTransitionGeometry &&
      other.size == size &&
      other.conversation == conversation &&
      other.orb == orb;

  @override
  int get hashCode => Object.hash(size, conversation, orb);

  @override
  String toString() =>
      'DesktopTransitionGeometry(size: $size, conversation: $conversation, '
      'orb: $orb)';
}

/// How the always-on-screen desktop window is presented.
enum DesktopPresentation {
  /// A small transparent presence resting on the desktop.
  orb,

  /// The full conversation surface.
  expanded,
}
