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
enum HostGenerationEventType {
  started,
  delta,
  completed,
  cancelled,
  failed,

  /// The model stopped to ask for tools. Terminal for the generation the
  /// way [completed] is; the caller runs the tools and continues the same
  /// session with a new generation carrying the results.
  toolCall,
}

/// Whether the app starts itself when the user logs in.
///
/// Read from the system rather than remembered, because it is the system's
/// state and not the app's: macOS keeps it across reinstalls, and the user
/// can revoke it in System Settings without the app being running to notice.
/// A stored copy would sooner or later claim something untrue about the
/// machine.
enum HostLoginItemStatus {
  /// The app does not start itself.
  off,

  /// The app starts itself at login.
  on,

  /// macOS has the registration but is waiting for the user to allow it in
  /// System Settings. Neither on nor off, and the difference matters: this
  /// is the state a switch that silently flipped back would be lying about.
  needsApproval,

  /// macOS refused this copy of the app: the signature is not one it will
  /// accept, or it could not find the bundle where it expected. Distinct
  /// from [needsApproval], which the user can fix, and from [unavailable],
  /// which no copy of the app could fix.
  refused,

  /// This macOS cannot do it at all. `SMAppService` is macOS 13 and the
  /// deployment target is 12.
  unavailable,
}

/// How the desktop window is currently presented.
///
/// The window is always on screen. In [orb] it is a small transparent presence
/// on the desktop; in [expanded] it is the full conversation surface.
enum HostPresentationMode { orb, expanded }

/// One conversation as the menu bar lists it.
class HostMenuConversation {
  HostMenuConversation({required this.conversationId, required this.title});

  /// Which conversation to open when the item is chosen.
  final String conversationId;

  /// What the item is called.
  final String title;
}

/// Every word the status-bar menu shows that is not a conversation title.
class HostMenuBarLabels {
  HostMenuBarLabels({
    required this.show,
    required this.hide,
    required this.talk,
    required this.recent,
    required this.quit,
    required this.activity,
  });

  /// Brings the conversation forward.
  final String show;

  /// Puts it away.
  final String hide;

  /// Starts talking.
  final String talk;

  /// Heads the list of recent conversations.
  final String recent;

  /// Ends the app.
  final String quit;

  /// What the agent is doing, empty when there is nothing to say.
  final String activity;
}

/// What the menu bar is currently showing.
///
/// Pushed rather than pulled: the menu is built by AppKit at the moment it
/// opens, and asking Dart for the list then would mean opening a menu that is
/// empty until an answer arrives.
class HostMenuBarState {
  HostMenuBarState({
    required this.conversations,
    required this.modelName,
    required this.canStartVoice,
    required this.labels,
  });

  /// The menu's own words, already in the user's language.
  ///
  /// Sent rather than written natively: the rest of the interface follows the
  /// system language through `AppLocalizations`, and there is none of that on
  /// the AppKit side. A menu that stayed English on a Chinese Mac would be the
  /// one part of the app that did not.
  final HostMenuBarLabels labels;

  /// The most recent conversations, in the order they should be listed.
  final List<HostMenuConversation> conversations;

  /// What the agent is thinking with, or empty while it is the preview.
  final String modelName;

  /// Whether voice can be started from the menu at all.
  final bool canStartVoice;
}

/// One button on the strip the resting orb shows under the pointer.
///
/// Drawn by AppKit rather than by Flutter, and that is forced rather than
/// chosen: the orb's square sits at the very bottom of the stage's frame, so
/// there is no room inside the window to draw anything beneath it, and the
/// window may never be resized to make room — a resize blocks the engine for
/// about a second. Its words still come from Dart for the same reason
/// [HostMenuBarLabels] does: the rest of the app follows the system language
/// and a strip that stayed English would be the one part that did not.
class HostOrbAction {
  HostOrbAction({
    required this.id,
    required this.symbol,
    required this.label,
    required this.engaged,
  });

  /// What to send back when this button is pressed.
  final String id;

  /// The SF Symbol drawn on it.
  final String symbol;

  /// What it is called, already in the user's language.
  final String label;

  /// Whether it is currently on — a microphone that is already listening.
  final bool engaged;
}

/// What the resting orb offers, in the order it should offer it.
///
/// Pushed rather than pulled, like the menu bar: the strip is drawn by AppKit
/// the instant the pointer arrives, and asking Dart for it then would show an
/// empty strip until the answer came back. An empty list turns it off.
class HostOrbActions {
  HostOrbActions({required this.actions});

  /// The buttons, leading to trailing.
  final List<HostOrbAction> actions;
}

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

/// Who said one remembered turn.
enum HostTurnRole { user, assistant }

/// A turn the runtime did not hear, replayed so it can.
///
/// The conversation on screen is read back from SQLite; the model behind it
/// is not, and a session that outlived a relaunch or a model swap starts
/// empty. These seed it.
class HostConversationTurn {
  HostConversationTurn({required this.role, required this.text});

  HostTurnRole role;
  String text;
}

class HostGenerationRequest {
  HostGenerationRequest({
    required this.generationId,
    required this.sessionId,
    required this.systemInstruction,
    required this.prompt,
    required this.context,
    required this.history,
    required this.temperature,
    required this.topP,
    required this.maxTokens,
    required this.seed,
    this.toolsJson,
    this.toolResponsesJson,
    this.imagePath,
  });

  String generationId;
  String sessionId;

  /// Who the agent is, identical for every turn of [sessionId].
  ///
  /// Kept apart from [prompt] so the runtime can prefill it once. Sent inside
  /// every question instead, it was measured costing 1.4 seconds of extra
  /// time to the first token on every turn.
  String systemInstruction;
  String prompt;
  List<String> context;

  /// What was already said, oldest first, excluding [prompt].
  ///
  /// Only consulted when the runtime has no live session for [sessionId]:
  /// a conversation that is still alive is its own memory, and seeding it
  /// again would say everything twice.
  List<HostConversationTurn> history;
  double temperature;
  double topP;
  int maxTokens;
  int seed;

  /// Tool declarations the model may call, as OpenAPI function JSON, or
  /// null for a conversation with nothing to declare. Opaque to the host:
  /// what exists and what it does are decided on this side, and the
  /// runtime's only part is rendering them into the chat template.
  String? toolsJson;

  /// Results answering the previous generation's tool calls, as
  /// `[{"name","id","response"}]` JSON. Non-null makes this a continuation
  /// of the same session: [prompt] is ignored — and may be empty — because
  /// the user's words were sent by the generation that asked for the tools.
  String? toolResponsesJson;

  /// A picture this question is about, as a path the runtime reads itself,
  /// or null for a question made of words alone.
  String? imagePath;
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

  /// The calls a [HostGenerationEventType.toolCall] event carries, as
  /// `[{"name","id","arguments"}]` JSON; null on every other type.
  String? toolCallsJson;
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

/// One place Apple Maps returned for a query.
class HostPlaceHit {
  /// Creates the hit.
  HostPlaceHit({required this.name, required this.address});

  /// What the place calls itself.
  final String name;

  /// Where it is, as Apple formats the address.
  final String address;
}

/// One event read from the user's calendar.
class HostCalendarEvent {
  /// Creates the event.
  HostCalendarEvent({
    required this.title,
    required this.startIso,
    required this.endIso,
    required this.calendar,
    required this.allDay,
  });

  /// What the event is called.
  final String title;

  /// Start, ISO-8601 local time.
  final String startIso;

  /// End, ISO-8601 local time.
  final String endIso;

  /// Which calendar it lives on.
  final String calendar;

  /// Whether it spans whole days rather than hours.
  final bool allDay;
}

/// A calendar read, carrying whether it was allowed to happen.
///
/// Authorization travels with the events because their absence is
/// ambiguous without it: an empty window means "free" only when the app
/// was allowed to look, and the model must be able to tell the difference.
class HostCalendarAnswer {
  /// Creates the answer.
  HostCalendarAnswer({required this.authorized, required this.events});

  /// Whether the user has granted calendar access.
  final bool authorized;

  /// The events in the asked window.
  final List<HostCalendarEvent> events;
}

@HostApi()
abstract class DesktopHostApi {
  @async
  HostHandshakeResult handshake(HostRequest request);

  /// Searches Apple Maps for places matching [query] and returns real
  /// names with addresses, or an empty list when nothing matched or the
  /// search failed.
  ///
  /// Runs natively because `MKLocalSearch` is a system framework: the
  /// query goes where the user's own Maps searches go, with no key to
  /// manage and no third party learning what was asked. No location is
  /// attached — the caller puts the city or district in the query instead.
  @async
  List<HostPlaceHit> searchPlaces(HostRequest request, String query);

  /// Reads the user's calendar events between [startIso] and [endIso].
  ///
  /// Access is EventKit's own permission: the first call has the system
  /// ask the user directly, and a denial comes back as `authorized: false`
  /// rather than an empty window pretending to be a free day.
  @async
  HostCalendarAnswer readCalendar(
    HostRequest request,
    String startIso,
    String endIso,
  );

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

  /// Asks the user where to write [contents], and writes it there.
  ///
  /// Returns the path written, or empty if the user backed out. The write
  /// happens natively for the same reason the chooser does: a sandboxed app
  /// may write where a save panel says and nowhere else, so handing the path
  /// back to Dart to write to would land outside the grant the panel gave.
  @async
  String saveTextFile(
    HostRequest request,
    String suggestedName,
    String contents,
  );

  /// Asks the user for a text file to ask questions about, and returns its
  /// path, or empty if they backed out.
  ///
  /// The chooser is the system's own, so the app is never told where files
  /// live. Unlike the recording handed to the transcriber, this one is read
  /// by the app itself — the sandbox grant `NSOpenPanel` issues belongs to
  /// this process, which is the process doing the reading.
  @async
  String chooseTextFile(HostRequest request);

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

  /// Tells the menu bar what to show the next time it is opened.
  void setMenuBarState(HostRequest request, HostMenuBarState state);

  /// Tells the resting orb what to offer the next time it is hovered.
  void setOrbActions(HostRequest request, HostOrbActions actions);

  /// Whether the app currently starts itself when the user logs in.
  @async
  HostLoginItemStatus loginItemStatus(HostRequest request);

  /// Asks macOS to start the app at login, or to stop.
  ///
  /// Returns the status that actually resulted, which is not always the one
  /// asked for — macOS may hold the registration pending the user's approval
  /// in System Settings. The caller shows what came back rather than what it
  /// requested.
  @async
  HostLoginItemStatus setLaunchAtLogin(HostRequest request, bool enabled);

  /// Takes one screenshot of the window the user was last working in, for a
  /// question they just asked about it.
  ///
  /// The invited look and nothing more: capture happens only inside this
  /// call, the user's tap is the consent, and the first call is where macOS
  /// asks for Screen Recording. The previous look's file is deleted when
  /// the next capture happens — the app is not a recorder, and keeps no
  /// archive of the user's screen.
  @async
  HostScreenLookResult captureScreenLook(HostRequest request);
}

/// How asking for a look at the screen ended.
enum HostScreenLookStatus {
  /// A screenshot was written; `path` names it.
  captured,

  /// macOS refused: Screen Recording is off for this app. The user can
  /// grant it in System Settings › Privacy & Security.
  denied,

  /// This macOS cannot do it (the capture API needs macOS 14).
  unavailable,

  /// Permission is fine and the capture still failed — no window to
  /// capture, or the write failed.
  failed,
}

/// One attempted look at the screen.
class HostScreenLookResult {
  HostScreenLookResult({required this.status, required this.path});

  /// How it ended.
  final HostScreenLookStatus status;

  /// Where the screenshot was written, or empty unless [status] is
  /// [HostScreenLookStatus.captured].
  final String path;
}

@FlutterApi()
abstract class DesktopHostEventApi {
  void onGenerationEvent(HostGenerationEvent event);

  void onPresentationModeChanged(HostPresentationMode mode);

  /// The user chose a conversation from the menu bar.
  void onMenuBarConversationChosen(String conversationId);

  /// The user asked for voice from the menu bar.
  void onMenuBarVoiceRequested();

  /// Text the user sent from another app's Services menu.
  ///
  /// Selecting a paragraph in Mail and asking Lulo about it used to mean
  /// copy, switch, paste, type the request, wait, copy the answer, switch
  /// back. This is the same thing in one step from where they already are.
  ///
  /// Send-only: the answer appears in Lulo rather than replacing what was
  /// selected. Writing back needs `NSReturnTypes` and a Services handler
  /// that blocks on an answer from the Dart isolate, which is a different
  /// and riskier shape.
  void onServiceTextReceived(String text);

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

  /// The user pressed one of the buttons under the resting orb.
  ///
  /// Only the identifier crosses: what each one means is decided in Dart,
  /// where the conversation, the voice and the screen look already live.
  void onOrbActionInvoked(String actionId);

  /// The app the user activated, by its visible name.
  ///
  /// Sent on every activation of an app that is not this one — summoning
  /// Lulo makes Lulo frontmost, and the question is about where the user
  /// came from. Pushed rather than pulled because a question is composed
  /// synchronously, and an app switch is a rare event where a poll would
  /// be a channel hop on every turn. Whether it is ever *used* is a
  /// setting, applied on the Dart side where the setting lives.
  void onFrontmostAppChanged(String name);

  /// Tells the app the window's frame has changed under its layout.
  ///
  /// The forms are laid out against the window's frame, and the frame belongs
  /// to the user: they resize it, zoom it, and take it full screen. Without
  /// this the conversation keeps drawing at the size the window no longer is.
  void onPresentationGeometryChanged(HostTransitionGeometry geometry);
}
