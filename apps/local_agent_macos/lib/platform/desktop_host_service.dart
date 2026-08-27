import 'dart:ui' show Offset, Rect, Size;
import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';

import '../generated/desktop_host_api.g.dart';

/// App-facing contract for the typed macOS host boundary.
/// Every word the status-bar menu shows that is not a conversation title.
///
/// Carried across rather than written natively: the rest of the interface
/// follows the system language and there are no localizations on the AppKit
/// side, so a menu that composed its own titles would be the one part of the
/// app that stayed English on a Chinese Mac.
final class DesktopMenuBarLabels {
  /// Creates the menu's words, already in the user's language.
  const DesktopMenuBarLabels({
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

/// What the agent is doing, as the status-bar menu says it.
enum DesktopAgentActivity {
  /// Waiting to be asked something.
  idle,

  /// The microphone is open.
  listening,

  /// An answer is being produced.
  thinking,

  /// An answer is being read aloud.
  speaking,

  /// Something is running that is neither of the above.
  working,

  /// Something needs the user.
  error,
}

/// The whole native boundary the conversation feature talks to.
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

/// One place Apple Maps returned: a real name at a real address.
final class DesktopPlaceHit {
  /// Creates the hit.
  const DesktopPlaceHit({required this.name, required this.address});

  /// What the place calls itself.
  final String name;

  /// Where it is, as Apple formats it.
  final String address;
}

/// One event read from the user's calendar.
final class DesktopCalendarEvent {
  /// Creates the event.
  const DesktopCalendarEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.calendar,
    required this.allDay,
  });

  /// What the event is called.
  final String title;

  /// When it starts, local time.
  final DateTime start;

  /// When it ends, local time.
  final DateTime end;

  /// Which calendar it lives on.
  final String calendar;

  /// Whether it spans whole days rather than hours.
  final bool allDay;
}

/// A calendar read, carrying whether it was allowed to happen.
final class DesktopCalendarAnswer {
  /// Creates the answer.
  const DesktopCalendarAnswer({required this.authorized, required this.events});

  /// Whether the user has granted calendar access.
  final bool authorized;

  /// The events in the asked window.
  final List<DesktopCalendarEvent> events;
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

/// One remembered turn, on its way to a runtime that never heard it.
final class DesktopConversationTurn {
  /// Creates a turn authored by [role] carrying [text].
  const DesktopConversationTurn({required this.role, required this.text});

  /// Who said it.
  final TurnRole role;

  /// What was said.
  final String text;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is DesktopConversationTurn &&
        role == other.role &&
        text == other.text;
  }

  @override
  int get hashCode => Object.hash(role, text);
}

/// Typed generation payload crossing the native boundary.
final class DesktopGenerationRequest {
  /// Creates an immutable generation request.
  const DesktopGenerationRequest({
    required this.generationId,
    required this.sessionId,
    required this.systemInstruction,
    required this.prompt,
    required this.context,
    required this.temperature,
    required this.topP,
    required this.maxTokens,
    required this.seed,
    this.history = const <DesktopConversationTurn>[],
    this.toolsJson,
    this.toolResponsesJson,
    this.imagePath,
  });

  /// What was already said, oldest first, excluding [prompt].
  ///
  /// The runtime consults this only when it has no live session for
  /// [sessionId]. A conversation still held in memory is its own record;
  /// seeding a live one would repeat everything it already knows.
  final List<DesktopConversationTurn> history;

  /// Stable ID used to correlate acknowledgements and events.
  final String generationId;

  /// Session whose native context should be used.
  final String sessionId;

  /// Who the agent is, identical for every turn of [sessionId].
  ///
  /// Held apart from [prompt] so the runtime can prefill it once instead of
  /// re-reading it with every question.
  final String systemInstruction;

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

  /// Tool declarations the model may call, as OpenAPI function JSON, or
  /// null when this conversation has nothing to declare.
  final String? toolsJson;

  /// Results answering the previous generation's tool calls, as
  /// `[{"name","id","response"}]` JSON. Non-null makes this a continuation
  /// of the same session: [prompt] is ignored, because the user's words
  /// were sent by the generation that asked for the tools.
  final String? toolResponsesJson;

  /// A picture this question is about, as a path the runtime reads itself,
  /// or null for a question made of words alone.
  final String? imagePath;
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
    this.toolCallsJson,
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

  /// The calls a [HostGenerationEventType.toolCall] event carries, as
  /// `[{"name","id","arguments"}]` JSON; null on every other type.
  final String? toolCallsJson;
}

/// Whether the app starts itself when the user logs in.
///
/// Read from the system every time rather than remembered. The registration
/// belongs to macOS — it survives reinstalls, and the user can revoke it in
/// System Settings without this app running to notice — so a stored copy
/// would eventually claim something untrue about the machine.
enum DesktopLoginItem {
  /// The app does not start itself.
  off,

  /// The app starts itself at login.
  on,

  /// macOS holds the registration and is waiting for the user to allow it in
  /// System Settings. Shown as its own state because a switch that flipped
  /// back with no explanation would read as a bug in the app.
  needsApproval,

  /// macOS refused this copy of the app — a signature it will not accept,
  /// or a bundle it could not find. The user cannot fix it from here, and
  /// showing it as plain [off] is how they end up tapping a switch that
  /// silently does nothing.
  refused,

  /// This macOS cannot do it at all: `SMAppService` is macOS 13 and the
  /// deployment target is 12. Unlike [refused], no copy of the app helps.
  unavailable,
}

/// How one invited look at the screen ended.
enum DesktopScreenLookStatus {
  /// A screenshot exists at [DesktopScreenLook.path].
  captured,

  /// macOS refused: Screen Recording is off for this app.
  denied,

  /// This macOS cannot capture (the API needs macOS 14).
  unavailable,

  /// Permission was fine and the capture still failed.
  failed,
}

/// One attempted look at the screen.
final class DesktopScreenLook {
  /// Creates a look result.
  const DesktopScreenLook({required this.status, this.path = ''});

  /// How it ended.
  final DesktopScreenLookStatus status;

  /// Where the screenshot was written, or empty unless captured.
  final String path;
}

/// One button on the strip the resting orb shows under the pointer.
///
/// Drawn by AppKit, because the orb's square sits at the very bottom of the
/// stage's frame and the window may never be resized to make room beneath it.
/// Its words are composed here anyway, so the strip speaks whatever the rest
/// of the app speaks.
final class DesktopOrbAction {
  /// Describes one button.
  const DesktopOrbAction({
    required this.id,
    required this.symbol,
    required this.label,
    this.engaged = false,
  });

  /// What comes back on [DesktopPresentationHost.orbActionInvocations] when
  /// this button is pressed.
  final String id;

  /// The SF Symbol drawn on it.
  final String symbol;

  /// What it is called, for its tooltip and for VoiceOver.
  final String label;

  /// Whether it is currently on — a microphone that is already listening.
  final bool engaged;

  /// Two buttons are the same when everything drawn on them is.
  @override
  bool operator ==(Object other) =>
      other is DesktopOrbAction &&
      other.id == id &&
      other.symbol == symbol &&
      other.label == label &&
      other.engaged == engaged;

  /// Hashes the fields compared above.
  @override
  int get hashCode => Object.hash(id, symbol, label, engaged);
}

/// How one write into the user's own notes ended.
enum DesktopVaultStatus {
  /// The entry is on disk.
  written,

  /// No folder has been chosen, so there was nowhere to write.
  noVault,

  /// The folder was chosen once and macOS will not hand it back — it was
  /// moved, deleted, or the grant did not survive.
  denied,

  /// It was reached and the write failed anyway.
  failed,
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

  /// Whether the app currently starts itself when the user logs in.
  Future<DesktopLoginItem> loginItem();

  /// Asks macOS to start the app at login, or to stop.
  ///
  /// Returns what actually resulted, which is not always what was asked for:
  /// macOS can hold the registration pending the user's approval. Callers
  /// show what came back rather than what they requested.
  Future<DesktopLoginItem> setLaunchAtLogin({required bool enabled});

  /// Drags the window by [delta], in logical points.
  Future<void> moveWindowBy(Offset delta);

  /// Requests from the menu bar to show the app's settings.
  Stream<void> get settingsRequests;

  /// Conversations the user chose from the status-bar menu.
  Stream<ConversationId> get menuConversationRequests;

  /// Requests to start talking, made from the status-bar menu.
  Stream<void> get menuVoiceRequests;

  /// Tells the resting orb what to offer the next time it is hovered.
  ///
  /// Pushed rather than pulled for the same reason the menu bar's contents
  /// are: the strip is drawn by AppKit the instant the pointer settles, and
  /// asking across the channel then would show an empty one until the answer
  /// arrived. An empty list turns the strip off.
  Future<void> setOrbActions(List<DesktopOrbAction> actions);

  /// Buttons pressed on the resting orb, by their identifier.
  Stream<String> get orbActionInvocations;

  /// Requests for an empty conversation, from File ▸ New (⌘N).
  Stream<void> get newConversationRequests;

  /// Requests to see what has already been said, from File ▸ Conversations…
  Stream<void> get conversationsRequests;

  /// Asks the user for the folder in their notes to write into.
  ///
  /// Returns its path, or empty if they backed out. A sandboxed app reaches
  /// only what a panel handed it, so this is also where the lasting grant is
  /// taken — without one the app would have to ask again on every launch.
  Future<String> chooseVaultFolder();

  /// The folder currently being written into, or empty if there is none.
  ///
  /// Resolved from the stored grant rather than remembered as a string: a
  /// path that no longer opens is not a folder, and a Settings pane showing
  /// one that cannot be written to is the failure this makes visible.
  Future<String> vaultFolder();

  /// Stops writing into the user's notes and forgets how to reach them.
  Future<void> forgetVaultFolder();

  /// Appends one entry to [fileName] in the chosen folder.
  ///
  /// [header] is written only when the file does not exist yet. Nothing
  /// already on disk is ever rewritten: the file is in somebody else's vault.
  Future<DesktopVaultStatus> appendToVault({
    required String fileName,
    required String header,
    required String entry,
  });

  /// Text the user sent from another app's Services menu.
  ///
  /// Selecting a paragraph elsewhere and asking Lulo about it used to be six
  /// steps: copy, switch, paste, type the request, wait, copy the answer
  /// back. This is that in one, from where they already are.
  Stream<String> get serviceText;

  /// The visible name of the app the user was last in, or empty before any
  /// switch has been seen.
  ///
  /// Latest-value rather than a stream, because its one reader composes a
  /// question synchronously and wants what is true now, not a history of
  /// switches. Whether it is ever used is a setting the reader applies.
  ValueListenable<String> get frontmostApp;

  /// Takes one screenshot of the window the user was last working in.
  ///
  /// The invited look: capture happens only inside this call, the user's
  /// tap is the consent, and the first call is where macOS asks for
  /// Screen Recording. The app keeps no archive — each capture deletes
  /// the previous look's file first.
  Future<DesktopScreenLook> captureScreenLook();

  /// Tells the status-bar menu what to show the next time it opens.
  ///
  /// Pushed rather than pulled: AppKit builds the menu at the moment it is
  /// opened, so a menu that asked across the channel then would be empty
  /// until an answer arrived.
  Future<void> setMenuBarState({
    required List<({ConversationId id, String title})> conversations,
    required String modelName,
    required DesktopAgentActivity activity,
    required bool canStartVoice,
    required DesktopMenuBarLabels labels,
  });

  /// Asks the user for a model file, returning its path or empty when they
  /// keep what they had.
  Future<String> chooseModelFile();

  /// Asks the user where to write [contents] and writes it there.
  ///
  /// Returns the path written, or empty if they backed out. Written natively
  /// because a sandboxed app may write where a save panel says and nowhere
  /// else — handing the path back here to write to would land outside the
  /// grant the panel gave.
  Future<String> saveTextFile({
    required String suggestedName,
    required String contents,
  });

  /// Asks the user for a text file to ask questions about.
  ///
  /// Returns its path, or empty if they backed out. Read by the app itself
  /// rather than handed to a helper: the grant `NSOpenPanel` issues belongs
  /// to this process, and this is the process doing the reading.
  Future<String> chooseTextFile();

  /// Searches Apple Maps for places matching [query].
  ///
  /// Empty when nothing matched or the search failed. No location is
  /// attached; the caller names the city or district in the query.
  Future<List<DesktopPlaceHit>> searchPlaces(String query);

  /// Reads the user's calendar between [from] and [to], local time.
  ///
  /// The first read has the system ask the user for calendar access; a
  /// denial comes back as an unauthorized answer, never as an empty
  /// window pretending to be a free day.
  Future<DesktopCalendarAnswer> readCalendar({
    required DateTime from,
    required DateTime to,
  });

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

  /// The window's frame changing under the layout: resized, zoomed, or taken
  /// full screen.
  ///
  /// The frame belongs to the user, so the forms are laid out against
  /// whatever it currently is rather than against a size chosen at launch.
  Stream<DesktopTransitionGeometry> get geometryChanges;

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
    this.fullScreen = false,
  });

  /// Size of the window covering both forms.
  final Size size;

  /// Where the conversation sits inside that window.
  final Rect conversation;

  /// Where the resting orb sits inside that window.
  final Rect orb;

  /// Whether the window is the screen.
  ///
  /// Full screen keeps the close, minimise and zoom buttons away until the
  /// pointer visits the top of the screen, so the room the layout normally
  /// leaves for them would sit there as a meaningless blank.
  final bool fullScreen;

  @override
  bool operator ==(Object other) =>
      other is DesktopTransitionGeometry &&
      other.size == size &&
      other.conversation == conversation &&
      other.orb == orb &&
      other.fullScreen == fullScreen;

  @override
  int get hashCode => Object.hash(size, conversation, orb, fullScreen);

  @override
  String toString() =>
      'DesktopTransitionGeometry(size: $size, conversation: $conversation, '
      'orb: $orb, fullScreen: $fullScreen)';
}

/// How the always-on-screen desktop window is presented.
enum DesktopPresentation {
  /// A small transparent presence resting on the desktop.
  orb,

  /// The full conversation surface.
  expanded,
}
