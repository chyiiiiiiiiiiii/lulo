import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'apps/local_agent_macos/lib/generated/desktop_host_api.g.dart',
    dartOptions: DartOptions(),
    swiftOut:
        'apps/local_agent_macos/macos/Runner/GeneratedDesktopHostApi.swift',
    swiftOptions: SwiftOptions(),
    dartPackageName: 'local_agent_macos',
  ),
)
enum HostGenerationEventType { started, delta, completed, cancelled, failed }

/// How the desktop window is currently presented.
///
/// The window is always on screen. In [orb] it is a small transparent presence
/// on the desktop; in [expanded] it is the full conversation surface.
enum HostPresentationMode { orb, expanded }

enum HostFailureCode {
  modelNotInstalled,
  modelLoadFailed,
  runtimeUnavailable,
  generationBusy,
  generationFailed,
  cancelled,
  protocolMismatch,
}

class HostRequest {
  HostRequest({
    required this.schemaVersion,
    required this.requestId,
    required this.timestampMicros,
  });

  int schemaVersion;
  String requestId;
  int timestampMicros;
}

class HostHandshakeResult {
  HostHandshakeResult({
    required this.schemaVersion,
    required this.runtimeName,
    required this.supportsStreaming,
    required this.supportsCancellation,
  });

  int schemaVersion;
  String runtimeName;
  bool supportsStreaming;
  bool supportsCancellation;
}

class HostModelRequest {
  HostModelRequest({
    required this.modelId,
    required this.modelPath,
    required this.contextSize,
  });

  String modelId;
  String modelPath;
  int contextSize;
}

class HostModelLoadResult {
  HostModelLoadResult({required this.modelId, required this.loaded});

  String modelId;
  bool loaded;
}

class HostGenerationRequest {
  HostGenerationRequest({
    required this.generationId,
    required this.sessionId,
    required this.prompt,
    required this.context,
    required this.temperature,
    required this.topP,
    required this.maxTokens,
    required this.seed,
  });

  String generationId;
  String sessionId;
  String prompt;
  List<String> context;
  double temperature;
  double topP;
  int maxTokens;
  int seed;
}

class HostGenerationAcknowledgement {
  HostGenerationAcknowledgement({
    required this.generationId,
    required this.accepted,
  });

  String generationId;
  bool accepted;
}

class HostCancellationAcknowledgement {
  HostCancellationAcknowledgement({
    required this.generationId,
    required this.acknowledged,
  });

  String generationId;
  bool acknowledged;
}

class HostOperationCompletion {
  HostOperationCompletion({required this.completed});

  bool completed;
}

class HostGenerationEvent {
  HostGenerationEvent({
    required this.schemaVersion,
    required this.generationId,
    required this.sequence,
    required this.type,
    this.delta,
    this.failureCode,
    this.message,
  });

  int schemaVersion;
  String generationId;
  int sequence;
  HostGenerationEventType type;
  String? delta;
  HostFailureCode? failureCode;
  String? message;
}

/// The canvas a change of form is drawn on, in Flutter logical points.
///
/// While the window is settling between the two forms it is grown to cover
/// both of them, so the presence can be drawn travelling from one to the other
/// instead of being cut off at the edge of whichever window is current. Every
/// rectangle here is measured from the top-left of that grown window.
class HostTransitionGeometry {
  HostTransitionGeometry({
    required this.width,
    required this.height,
    required this.conversationLeft,
    required this.conversationTop,
    required this.conversationWidth,
    required this.conversationHeight,
    required this.orbLeft,
    required this.orbTop,
    required this.orbExtent,
    required this.fullScreen,
  });

  double width;
  double height;
  double conversationLeft;
  double conversationTop;
  double conversationWidth;
  double conversationHeight;
  double orbLeft;
  double orbTop;
  double orbExtent;

  /// Whether the window is the screen.
  ///
  /// Full screen keeps the close, minimise and zoom buttons off the window
  /// until the pointer visits the top of the screen, so the room the layout
  /// normally leaves for them would sit there as a meaningless blank.
  bool fullScreen;
}

@HostApi()
abstract class DesktopHostApi {
  @async
  HostHandshakeResult handshake(HostRequest request);

  @async
  HostModelLoadResult loadModel(HostRequest request, HostModelRequest model);

  @async
  HostGenerationAcknowledgement startGeneration(
    HostRequest request,
    HostGenerationRequest generation,
  );

  @async
  HostCancellationAcknowledgement cancelGeneration(
    HostRequest request,
    String generationId,
  );

  @async
  HostOperationCompletion resetSession(HostRequest request, String sessionId);

  @async
  HostOperationCompletion unloadModel(HostRequest request);

  void showPanel(HostRequest request);

  void hidePanel(HostRequest request);

  void togglePanel(HostRequest request);

  void setPresentationMode(HostRequest request, HostPresentationMode mode);

  /// Moves the window by a delta in logical points, for dragging the orb.
  void moveWindowBy(HostRequest request, double deltaX, double deltaY);

  /// Asks the user for a model file and returns its path, or empty.
  ///
  /// The chooser is the system's own, so the app never has to be told where
  /// files live or be trusted with a path the user did not pick.
  @async
  String chooseModelFile(HostRequest request);

  /// Applies the user's choices about how the resting orb behaves.
  ///
  /// Held natively rather than consulted per change of form, because the
  /// window has to behave correctly even when the app is busy.
  void setWindowBehaviour(
    HostRequest request,
    bool keepOrbOnTop,
    bool followAcrossSpaces,
  );

  /// Where each form sits inside the window, which never changes size.
  ///
  /// Needed at rest and not only during a change of form: both forms are
  /// drawn inside one window, so each has to be placed rather than filling it.
  HostTransitionGeometry presentationGeometry(HostRequest request);

  /// Grows the window to cover both forms and stops it taking the mouse.
  ///
  /// Returns where each form sits inside that grown window, so the move
  /// between them is drawn by Flutter on one canvas and one clock. Animating
  /// the window itself instead would put the frame on AppKit's clock and the
  /// presence on Flutter's, and the two drift apart.
  @async
  HostTransitionGeometry beginPresentationTransition(
    HostRequest request,
    HostPresentationMode target,
  );

  /// Settles the window into [mode] and lets it take the mouse again.
  void endPresentationTransition(
    HostRequest request,
    HostPresentationMode mode,
  );
}

@FlutterApi()
abstract class DesktopHostEventApi {
  void onGenerationEvent(HostGenerationEvent event);

  void onPresentationModeChanged(HostPresentationMode mode);

  /// Asks the app to change form, rather than telling it that it already did.
  ///
  /// The hotkey and the menu bar live on the native side, so without this the
  /// window would already have moved by the time Flutter heard about it and
  /// the presence could not be drawn travelling. The host settles the window
  /// itself if the app does not answer, so the hotkey still works when the
  /// Dart side is busy or wedged.
  void onPresentationChangeRequested(HostPresentationMode target);

  /// Asks the app to show its settings, from the menu bar or its shortcut.
  void onSettingsRequested();

  /// Tells the app the window's frame has changed under its layout.
  ///
  /// The forms are laid out against the window's frame, and the frame belongs
  /// to the user: they resize it, zoom it, and take it full screen. Without
  /// this the conversation keeps drawing at the size the window no longer is.
  void onPresentationGeometryChanged(HostTransitionGeometry geometry);
}
