import 'dart:async';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../features/conversation/conversation_storage_service.dart';
import '../features/conversation/conversation_view.dart';
import '../features/conversation/export_file_name.dart';
import '../features/conversation/widgets/conversation_history_sheet.dart';
import '../features/model/first_run.dart';
import '../features/model/model_catalog.dart';
import '../features/presence/agent_presence_controller.dart';
import '../features/presence/agent_presence_orb.dart';
import '../features/presence/agent_presence_state.dart';
import '../features/presence/desktop_orb_surface.dart';
import '../features/presence/presence_flight.dart';
import '../features/settings/app_settings.dart';
import '../features/settings/settings_sheet.dart';
import '../features/voice/voice_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../platform/desktop_host_service.dart';
import 'app_composition.dart';

/// Root application widget that owns the application composition lifecycle.
final class LocalAgentApp extends StatefulWidget {
  /// Creates the local agent application.
  const LocalAgentApp({
    required this.composition,
    this.presenceShaderLoader = loadAgentPresenceShader,
    super.key,
  });

  /// App-scoped dependency owner.
  final AppComposition composition;

  /// Loads the presence shader, with deterministic substitution in tests.
  final AgentPresenceShaderLoader presenceShaderLoader;

  @override
  State<LocalAgentApp> createState() => _LocalAgentAppState();
}

final class _LocalAgentAppState extends State<LocalAgentApp> {
  @override
  void dispose() {
    unawaited(widget.composition.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color seed = Color(0xFF7357E8);
    return MaterialApp(
      title: 'Lulo',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      // The system's language, not one chosen here. A Mac set to Traditional
      // Chinese and an agent answering in it should not be operated through
      // an English settings sheet.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: _theme(Brightness.light, seed),
      darkTheme: _theme(Brightness.dark, seed),
      home: _PresentationSwitch(
        composition: widget.composition,
        presenceShaderLoader: widget.presenceShaderLoader,
      ),
    );
  }
}

/// Chooses the surface for the window's current form.
///
/// Only this widget rebuilds when the form changes, so switching between the
/// desktop orb and the conversation never rebuilds the conversation itself.
final class _PresentationSwitch extends StatefulWidget {
  const _PresentationSwitch({
    required this.composition,
    required this.presenceShaderLoader,
  });

  final AppComposition composition;
  final AgentPresenceShaderLoader presenceShaderLoader;

  @override
  State<_PresentationSwitch> createState() => _PresentationSwitchState();
}

final class _PresentationSwitchState extends State<_PresentationSwitch>
    with TickerProviderStateMixin {
  /// Identifies the conversation so it keeps its state when the form changes.
  ///
  /// Collapsing wraps the conversation differently so it can lay out at its own
  /// size inside an orb-sized window. That moves it in the tree, and without a
  /// stable identity Flutter would rebuild it from scratch: the view owns its
  /// ViewModel, so the answer being generated would be cancelled.
  ///
  /// Replaced only when the user changes conversation: that rebuild is the
  /// point, because the view owns its ViewModel and a new conversation is a
  /// new ViewModel.
  GlobalKey _conversationKey = GlobalKey();

  /// Identifies the one orb, so that changing form moves it.
  ///
  /// The header and the desktop are different places in the tree, and without a
  /// stable identity Flutter would destroy the orb in the form being left and
  /// build another in the form being entered. That restarts its clock and
  /// reloads its shader on every collapse; with the key the same orb is
  /// reparented and simply keeps running.
  final GlobalKey _orbKey = GlobalKey();

  /// Identifies the space the header keeps for the orb while it is away.
  ///
  /// Where the presence lands when the conversation is summoned. Its position
  /// depends on the title beside it, so it is measured rather than assumed.
  final GlobalKey _anchorKey = GlobalKey();

  /// The agent's presence, owned here because both forms show it.
  ///
  /// Created above the conversation rather than inside it: the desktop orb has
  /// to follow the same presence, and a controller owned by the form being
  /// left cannot outlive it.
  final AgentPresenceController _presence = AgentPresenceController();

  /// Drives the presence between the two forms.
  late final AnimationController _flight;

  /// Drives the conversation away and back: 0 is present, 1 is gone.
  ///
  /// Deliberately not the flight's clock. The flight cannot start until the
  /// window has been resized and its surface reallocated, and leaving depends
  /// on none of that, so it answers the keystroke straight away and covers
  /// the wait that would otherwise be a still screen.
  late final AnimationController _leaving;

  /// Where the presence starts and ends its journey, in canvas coordinates.
  Rect? _flightFrom;
  Rect? _flightTo;

  /// The canvas covering both forms, held only while the presence is moving.
  DesktopTransitionGeometry? _canvas;

  /// Where each form sits inside the window, which never changes size.
  ///
  /// Both forms are drawn inside one window, so each is placed rather than
  /// filling it. Until this arrives there is nothing to place anything
  /// against, which lasts one round trip at launch.
  DesktopTransitionGeometry? _stage;

  StreamSubscription<DesktopPresentation>? _requests;
  StreamSubscription<void>? _settingsRequests;
  StreamSubscription<DesktopTransitionGeometry>? _geometryChanges;

  /// The user's choices, and whether they are currently being looked at.
  AppSettings _settings = const AppSettings();
  bool _showingSettings = false;

  /// Whether the user has asked to look around without a model.
  ///
  /// Not persisted: an app with no model still has one thing to do, so the
  /// next launch offers it again. Installing a model is what retires this for
  /// good, because the offer is only made while there is nothing to think
  /// with.
  bool _lookedAround = false;

  /// The stored conversations, and whether they are currently being looked at.
  List<ConversationSummary> _conversations = const <ConversationSummary>[];
  bool _showingConversations = false;

  /// Which conversation the view was asked to hold.
  ///
  /// Null with [_startFresh] unset means the most recently spoken-in one,
  /// which is what launch resumes; null with it set means a deliberately new
  /// conversation.
  ConversationId? _openConversation;
  bool _startFresh = false;

  @override
  void initState() {
    super.initState();
    // Unbounded because the spring passes its destination before settling,
    // and built here rather than lazily: a controller first touched in dispose
    // would ask a deactivated element for its TickerMode.
    _flight = AnimationController.unbounded(vsync: this);
    _leaving = AnimationController(
      vsync: this,
      duration: leavingDuration,
      value:
          widget.composition.presentationHost?.presentation.value ==
              DesktopPresentation.orb
          ? 1
          : 0,
    );
    // The hotkey and the menu bar are native, so collapsing is asked for from
    // there. Without listening the window would simply move and there would be
    // nothing left to draw.
    _requests = widget.composition.presentationHost?.presentationRequests
        .listen(_flyTo);
    _presence.semanticStateListenable.addListener(_followPresenceIntoMenuBar);
    unawaited(_loadStage());
    final Future<void> settingsLoaded = _loadSettings();
    unawaited(settingsLoaded.then((void _) => _refreshMenuBar()));
    unawaited(settingsLoaded);
    // The status-bar menu is the one place outside the window where the user
    // can ask for something, so its items are answered the same way the
    // hotkey's are.
    _menuConversations = widget
        .composition
        .presentationHost
        ?.menuConversationRequests
        .listen((ConversationId conversationId) {
          unawaited(_openFromMenuBar(conversationId));
        });
    _menuVoice = widget.composition.presentationHost?.menuVoiceRequests.listen((
      void _,
    ) {
      unawaited(_openFromMenuBar(null, thenListen: true));
    });
    // A selection sent from another app. The window is already being shown
    // by the native side; this puts the text where the user can add what
    // they want done with it.
    _serviceText = widget.composition.presentationHost?.serviceText.listen(
      _composerSeed.add,
    );
    _settingsRequests = widget.composition.presentationHost?.settingsRequests
        .listen((void _) {
          // Not before the stored settings have arrived: the sheet applies
          // each flip over the settings it can see, and a sheet over the
          // defaults would save defaults-plus-one-flip, silently erasing
          // every stored choice.
          unawaited(
            settingsLoaded.then((void _) {
              if (mounted) {
                setState(() => _showingSettings = true);
              }
            }),
          );
        });
    // The window's frame belongs to the user — resized, zoomed, or taken full
    // screen — and the forms are laid out against it, so the layout follows.
    _geometryChanges = widget.composition.presentationHost?.geometryChanges
        .listen((DesktopTransitionGeometry stage) {
          if (mounted && _canvas == null) {
            setState(() => _stage = stage);
          }
        });
    // The form can also change without having been asked for here: the host
    // settles the window itself when the app does not answer in time. Leaving
    // follows the form as well as the flight, or the conversation is left
    // standing on a desktop that has already collapsed.
    widget.composition.presentationHost?.presentation.addListener(
      _followPresentation,
    );
  }

  void _followPresentation() {
    if (_canvas != null) {
      return;
    }
    final DesktopPresentation? mode =
        widget.composition.presentationHost?.presentation.value;
    _leaving.value = mode == DesktopPresentation.orb ? 1 : 0;
  }

  /// Fetches [entry], then thinks with it as soon as it is whole.
  ///
  /// Asked for by hand, so its completion is the activation the user meant.
  Future<void> _downloadModel(ModelCatalogEntry entry) async {
    final File model;
    try {
      model = await widget.composition.modelDownloads.download(entry);
    } on Object {
      // The manager already stands the row back up as not-installed; the
      // sheet is where the user learns the download did not finish.
      return;
    }
    if (!mounted) {
      return;
    }
    await _changeSettings(_settings.copyWith(modelPath: model.path));
  }

  /// Thinks with the already-installed [entry].
  void _useModel(ModelCatalogEntry entry) {
    final File? model = widget.composition.modelDownloads.installedFileOf(
      entry,
    );
    if (model != null && mounted) {
      unawaited(_changeSettings(_settings.copyWith(modelPath: model.path)));
    }
  }

  /// Reads the store and puts its conversations in front of the user.
  Future<void> _showConversations() async {
    _conversationQuery = '';
    final List<ConversationSummary> conversations = await widget.composition
        .listConversations();
    if (!mounted) {
      return;
    }
    setState(() {
      _conversations = conversations;
      _showingConversations = true;
    });
    unawaited(_refreshMenuBar());
  }

  /// Puts [conversationId] into the view, in place of what it held.
  void _openStoredConversation(ConversationId conversationId) {
    setState(() {
      _openConversation = conversationId;
      _startFresh = false;
      _conversationKey = GlobalKey();
      _showingConversations = false;
    });
  }

  /// Starts an empty conversation, leaving the stored ones where they are.
  void _startNewConversation() {
    unawaited(_refreshMenuBar());
    setState(() {
      _openConversation = null;
      _startFresh = true;
      _conversationKey = GlobalKey();
      _showingConversations = false;
    });
  }

  StreamSubscription<ConversationId>? _menuConversations;
  StreamSubscription<void>? _menuVoice;
  StreamSubscription<String>? _serviceText;

  /// Selections sent in from another app, for the composer to take.
  ///
  /// A stream rather than a held value: the same paragraph sent twice is two
  /// events, and a composer mounted later must not inherit an old one.
  final StreamController<String> _composerSeed =
      StreamController<String>.broadcast();

  /// The conversations the menu bar was last given.
  ///
  /// Kept so that a change of activity can be pushed without going back to
  /// the store: the presence moves several times a turn and the list does
  /// not move at all.
  List<({ConversationId id, String title})> _menuBarConversations =
      const <({ConversationId id, String title})>[];

  /// Follows the presence into the menu bar.
  ///
  /// The menu is the only place the agent's state is visible while the window
  /// is away, which is most of the time for a resident app.
  void _followPresenceIntoMenuBar() {
    unawaited(_pushMenuBar(reloadConversations: false));
  }

  /// What the presence is doing, in the terms the menu bar speaks.
  DesktopAgentActivity get _menuActivity =>
      switch (_presence.semanticStateListenable.value) {
        AgentPresenceState.idle => DesktopAgentActivity.idle,
        AgentPresenceState.listening => DesktopAgentActivity.listening,
        AgentPresenceState.thinking => DesktopAgentActivity.thinking,
        AgentPresenceState.speaking => DesktopAgentActivity.speaking,
        AgentPresenceState.working => DesktopAgentActivity.working,
        AgentPresenceState.error => DesktopAgentActivity.error,
      };

  /// Brings the window forward on a request from the status-bar menu.
  ///
  /// A menu item that only changed something behind a hidden window would
  /// look like it had done nothing.
  Future<void> _openFromMenuBar(
    ConversationId? conversationId, {
    bool thenListen = false,
  }) async {
    final DesktopPresentationHost? host = widget.composition.presentationHost;
    if (host == null) {
      return;
    }
    await host.setPresentation(DesktopPresentation.expanded);
    if (!mounted) {
      return;
    }
    // Everything that could be covering the conversation goes away first.
    // The settings sheet and the first-run offer are both opaque and fill the
    // window, so without this a menu item brings the window forward onto a
    // screen that has nothing to do with what was chosen — and on a fresh
    // install, where the first-run offer is up on every launch, every menu
    // conversation would be dead.
    setState(() {
      _showingSettings = false;
      _showingConversations = false;
      _lookedAround = true;
    });
    if (conversationId != null) {
      _openStoredConversation(conversationId);
    }
    if (thenListen) {
      widget.composition.voiceRequests.value += 1;
    }
  }

  /// Tells the status-bar menu what to show.
  ///
  /// Pushed on every change rather than answered on demand, because AppKit
  /// builds the menu at the moment it opens and there is nowhere to wait.
  Future<void> _refreshMenuBar() => _pushMenuBar(reloadConversations: true);

  /// Tells the status-bar menu what to show.
  Future<void> _pushMenuBar({required bool reloadConversations}) async {
    final DesktopPresentationHost? host = widget.composition.presentationHost;
    if (host == null) {
      return;
    }
    final AppLocalizations words = AppLocalizations.of(context);
    final DesktopAgentActivity activity = _menuActivity;
    if (reloadConversations) {
      final List<ConversationSummary> recent = await widget.composition
          .listConversations();
      if (!mounted) {
        return;
      }
      _menuBarConversations = <({ConversationId id, String title})>[
        for (final ConversationSummary summary in recent.take(3))
          (id: summary.id, title: summary.title),
      ];
    }
    await host.setMenuBarState(
      conversations: _menuBarConversations,
      modelName: _settings.modelPath.isEmpty
          ? ''
          : _settings.modelPath.split('/').last,
      activity: activity,
      canStartVoice: widget.composition.voiceService != null,
      labels: DesktopMenuBarLabels(
        show: words.menuShow,
        hide: words.menuHide,
        talk: words.menuTalk,
        recent: words.menuRecent,
        quit: words.menuQuit,
        activity: switch (activity) {
          DesktopAgentActivity.idle => words.activityIdle,
          DesktopAgentActivity.listening => words.activityListening,
          DesktopAgentActivity.thinking => words.activityThinking,
          DesktopAgentActivity.speaking => words.activitySpeaking,
          DesktopAgentActivity.working => words.activityWorking,
          DesktopAgentActivity.error => words.activityError,
        },
      ),
    );
  }

  /// What the user last typed into the list's search field.
  ///
  /// Held so that renaming or pinning re-reads the same narrowed list rather
  /// than throwing the user back to everything.
  String _conversationQuery = '';

  /// Narrows the list to what the user is looking for.
  Future<void> _searchConversations(String query) async {
    _conversationQuery = query;
    final List<ConversationSummary> found = await widget.composition
        .searchConversations(query);
    if (!mounted || _conversationQuery != query) {
      // A later keystroke has already asked a better question.
      return;
    }
    setState(() => _conversations = found);
  }

  /// Gives a conversation a name of the user's own.
  Future<void> _renameConversation(
    ConversationId conversationId,
    String title,
  ) async {
    await widget.composition.renameConversation(conversationId, title);
    unawaited(_refreshMenuBar());
    await _searchConversations(_conversationQuery);
  }

  /// Keeps a conversation at the top of the list, or lets it go.
  Future<void> _pinConversation(
    ConversationId conversationId, {
    required bool pinned,
  }) async {
    await widget.composition.setConversationPinned(
      conversationId,
      pinned: pinned,
    );
    unawaited(_refreshMenuBar());
    await _searchConversations(_conversationQuery);
  }

  /// Writes one conversation out as Markdown, wherever the user says.
  ///
  /// The whole store is on this machine and nothing backs it up, so this is
  /// the only way anything said to Lulo can leave it.
  Future<void> _exportConversation(ConversationId conversationId) async {
    final DesktopPresentationHost? host = widget.composition.presentationHost;
    if (host == null) {
      return;
    }
    final AppLocalizations words = AppLocalizations.of(context);
    final String title = _conversations
        .firstWhere(
          (ConversationSummary summary) => summary.id == conversationId,
          orElse: () => ConversationSummary(
            id: conversationId,
            title: words.conversationsTitle,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        )
        .title;
    try {
      // Inside the guard, not before it: a store that cannot be read is a
      // failed export too, and outside it that error escaped an unawaited
      // future with nothing said to anyone.
      final List<Turn> turns = await widget.composition.loadTurns(
        conversationId,
      );
      if (!mounted) {
        return;
      }
      await host.saveTextFile(
        suggestedName: '${exportFileName(title)}.md',
        contents: conversationToMarkdown(
          title: title,
          turns: turns,
          labels: ConversationLabels(
            user: words.roleYou,
            assistant: words.roleAssistant,
            interrupted: words.turnInterrupted,
            stopped: words.turnStopped,
            failed: words.turnFailed,
            doubted: words.heardDoubtLabel,
          ),
        ),
      );
    } on Object {
      if (!mounted) {
        return;
      }
      // A dialog rather than a snackbar. The conversation list is an opaque
      // sheet filling the window and it is still up at this moment, so a
      // snackbar animates in underneath it and the user is told nothing.
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          key: const Key('export-failed'),
          content: Text(words.exportFailed),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(words.reviseCancel),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _forgetConversation(ConversationId conversationId) async {
    // Launch resumes the most recently spoken-in conversation without naming
    // it here, so "the one being looked at" includes the head of the list the
    // user is deleting from.
    final bool wasOpen =
        conversationId == _openConversation ||
        (_openConversation == null &&
            // A deliberately fresh conversation is unstored: no row in the
            // list can be it, so no deletion should tear it down.
            !_startFresh &&
            _conversations.isNotEmpty &&
            conversationId == _conversations.first.id);
    await widget.composition.deleteConversation(conversationId);
    unawaited(_refreshMenuBar());
    final List<ConversationSummary> conversations = await widget.composition
        .listConversations();
    if (!mounted) {
      return;
    }
    setState(() {
      _conversations = conversations;
      if (wasOpen) {
        _openConversation = null;
        _startFresh = true;
        _conversationKey = GlobalKey();
      }
    });
  }

  /// Reads the user's choices and puts the window into them.
  Future<void> _loadSettings() async {
    AppSettings settings = await widget.composition.settingsStore.load();
    if (settings.modelPath.trim().isEmpty) {
      // Nothing chosen yet, but the recommended model is already here: think
      // with it rather than greeting the user with the canned preview. A
      // deliberate choice, once made, is never overridden.
      final ModelCatalogEntry? recommended = widget.composition.catalog
          .where((ModelCatalogEntry entry) => entry.recommended)
          .firstOrNull;
      final File? installed = recommended == null
          ? null
          : widget.composition.modelDownloads.installedFileOf(recommended);
      if (installed != null) {
        settings = settings.copyWith(modelPath: installed.path);
        await widget.composition.settingsStore.save(settings);
        await widget.composition.useModel(installed.path);
      }
    }
    if (!mounted) {
      return;
    }
    setState(() => _settings = settings);
    await _applySettings(settings);
    if (settings.openConversationOnLaunch) {
      await widget.composition.presentationHost?.setPresentation(
        DesktopPresentation.expanded,
      );
    }
  }

  /// Picks a recording, writes it out, and saves the text beside it.
  ///
  /// Returns the file name saved, empty when the user backed out of either
  /// panel, or null when nothing came back — which most often means the
  /// batch recogniser is not running, and the section next to this one says
  /// so by name.
  Future<(TranscribeOutcome, String?)> _transcribeRecording() async {
    if (_transcribing) {
      // The guard has to live here rather than in the section: the settings
      // sheet is unmounted whenever the window changes form, which destroyed
      // the widget's own flag and let a second job start against a
      // single-threaded sidecar — with a second open panel over the first
      // job's pending save panel.
      return (TranscribeOutcome.backedOut, null);
    }
    _transcribing = true;
    try {
      return await _runTranscription();
    } finally {
      _transcribing = false;
    }
  }

  /// Picks a file for questions to be answered out of.
  ///
  /// Read here rather than handed to a helper: the sandbox grant the open
  /// panel issues belongs to this process, and this is the process reading.
  /// Returns the file's name, empty when the user backed out, or null when
  /// it could not be read.
  Future<String?> _openDocument() async {
    final DesktopPresentationHost? host = widget.composition.presentationHost;
    if (host == null) {
      return null;
    }
    final String path = await host.chooseTextFile();
    if (path.isEmpty) {
      return '';
    }
    final String text;
    try {
      text = await File(path).readAsString();
    } on Object {
      return null;
    }
    widget.composition.openDocument.value = text;
    widget.composition.openDocumentName.value = _baseName(path);
    return widget.composition.openDocumentName.value;
  }

  /// Stops answering out of the open file.
  void _closeDocument() {
    widget.composition.openDocument.value = '';
    widget.composition.openDocumentName.value = null;
  }

  /// The last transcript the recogniser produced and nobody has saved.
  ///
  /// Held here rather than in the settings sheet, which is torn down every
  /// time the window changes form — ten minutes of the recogniser's work
  /// must not depend on a widget staying mounted.
  String? _heldTranscript;

  /// Offers the save panel again for a transcript already in hand.
  Future<(TranscribeOutcome, String?)> _saveHeldTranscript() async {
    final String? text = _heldTranscript;
    final DesktopPresentationHost? host = widget.composition.presentationHost;
    if (text == null || host == null) {
      return (TranscribeOutcome.backedOut, null);
    }
    return _save(text, suggested: _heldName ?? 'transcript.txt', host: host);
  }

  /// What the held transcript should be called.
  String? _heldName;

  /// Writes [text] through the save panel and reports what happened.
  Future<(TranscribeOutcome, String?)> _save(
    String text, {
    required String suggested,
    required DesktopPresentationHost host,
  }) async {
    final String written = await host.saveTextFile(
      suggestedName: suggested,
      contents: text,
    );
    if (written.isEmpty) {
      // Cancelled. The text stays in hand and the section offers to save it
      // again rather than asking the recogniser to redo the work.
      _heldTranscript = text;
      _heldName = suggested;
      return (TranscribeOutcome.heldUnsaved, null);
    }
    _heldTranscript = null;
    _heldName = null;
    return (TranscribeOutcome.saved, written.split('/').last);
  }

  /// True while a recording is being written out, whatever is on screen.
  bool _transcribing = false;

  /// The file's name without its extension.
  ///
  /// Splitting on the first dot turned `2026.08.07 lecture.m4a` — the
  /// ordinary shape of a dated 課堂錄音 — into `2026`, and a dotfile into
  /// nothing at all, which the save panel then showed as a file called
  /// `.txt` with no visible name.
  static String _baseName(String path) {
    final String file = path.split('/').last;
    final int dot = file.lastIndexOf('.');
    // A leading dot is a hidden file, not an extension separator.
    return dot > 0 ? file.substring(0, dot) : file;
  }

  Future<(TranscribeOutcome, String?)> _runTranscription() async {
    final VoiceService? voice = widget.composition.voiceService;
    final DesktopPresentationHost? host = widget.composition.presentationHost;
    if (voice == null || host == null) {
      return (TranscribeOutcome.failed, null);
    }
    final String path = await voice.chooseRecording();
    if (path.isEmpty) {
      return (TranscribeOutcome.backedOut, null);
    }
    final String text = await voice.transcribeRecording(path);
    if (text.trim().isEmpty) {
      return (TranscribeOutcome.failed, null);
    }
    // Written through the save panel for the same reason an export is: a
    // sandboxed app may write where the panel says and nowhere else.
    return _save(text, suggested: '${_baseName(path)}.txt', host: host);
  }

  /// Hands the choices to the window and writes them down.
  Future<void> _applySettings(AppSettings settings) async {
    widget.composition.ttsVoice.value = settings.ttsVoice;
    widget.composition.answerStyle.value = settings.answerStyle;
    widget.composition.shareFrontmostApp.value = settings.shareFrontmostApp;
    widget.composition.rememberFacts.value = settings.rememberFacts;
    await widget.composition.presentationHost?.setWindowBehaviour(
      keepOrbOnTop: settings.keepOrbOnTop,
      followAcrossSpaces: settings.followAcrossSpaces,
    );
  }

  /// Applies a choice as it is made, rather than behind a save button.
  Future<void> _changeSettings(AppSettings settings) async {
    final String wasThinkingWith = _settings.modelPath;
    setState(() => _settings = settings);
    await _applySettings(settings);
    await widget.composition.settingsStore.save(settings);
    if (!mounted) {
      // Torn down while saving: the composition is being disposed with the
      // widget, and asking it to load a model now would only throw.
      return;
    }
    if (settings.modelPath != wasThinkingWith) {
      // Only when it actually changed: loading a model costs seconds and
      // several gigabytes, and every other switch on this sheet would
      // otherwise pay for it.
      await widget.composition.useModel(settings.modelPath);
    }
  }

  Future<void> _loadStage() async {
    final DesktopPresentationHost? host = widget.composition.presentationHost;
    if (host == null) {
      return;
    }
    final DesktopTransitionGeometry stage = await host.presentationGeometry();
    if (!mounted) {
      return;
    }
    setState(() => _stage = stage);
  }

  @override
  void dispose() {
    unawaited(_requests?.cancel());
    _presence.semanticStateListenable.removeListener(
      _followPresenceIntoMenuBar,
    );
    unawaited(_menuConversations?.cancel());
    unawaited(_menuVoice?.cancel());
    unawaited(_serviceText?.cancel());
    unawaited(_composerSeed.close());
    unawaited(_settingsRequests?.cancel());
    unawaited(_geometryChanges?.cancel());
    widget.composition.presentationHost?.presentation.removeListener(
      _followPresentation,
    );
    _flight.dispose();
    _leaving.dispose();
    _presence.dispose();
    super.dispose();
  }

  /// The orb's top-left in the current window, before that window changes.
  Offset? _orbOrigin() {
    final BuildContext? context = _orbKey.currentContext;
    final RenderObject? object = context?.findRenderObject();
    if (object is! RenderBox || !object.hasSize) {
      return null;
    }
    return object.localToGlobal(Offset.zero);
  }

  /// Where the header keeps the orb's place, in canvas coordinates.
  Rect? _anchorRect() {
    final RenderObject? object = _anchorKey.currentContext?.findRenderObject();
    if (object is! RenderBox || !object.hasSize) {
      return null;
    }
    return object.localToGlobal(Offset.zero) & object.size;
  }

  Future<void> _nextFrame() {
    final Completer<void> frame = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!frame.isCompleted) {
        frame.complete();
      }
    });
    return frame.future;
  }

  /// Draws the presence travelling, then lets the window settle into [target].
  Future<void> _flyTo(DesktopPresentation target) async {
    final DesktopPresentationHost? host = widget.composition.presentationHost;
    if (host == null || _canvas != null) {
      return;
    }
    final bool collapsing = target == DesktopPresentation.orb;
    // The travelling presence is ornament. A user who asked the system for
    // less motion gets the change of form itself, at once.
    final bool reduceMotion =
        mounted && (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (reduceMotion) {
      _leaving.value = collapsing ? 1 : 0;
      await host.beginPresentationTransition(target);
      if (!mounted) {
        return;
      }
      await host.endPresentationTransition(target);
      return;
    }
    // Answered before anything is asked of the host, so the keystroke has a
    // visible effect while the window is still being prepared.
    if (collapsing) {
      unawaited(_leaving.forward());
    }
    // Measured before the window grows, so it is still in the coordinates of
    // the form being left.
    final Offset? origin = _orbOrigin();

    final DesktopTransitionGeometry canvas = await host
        .beginPresentationTransition(target);
    if (!mounted) {
      return;
    }

    // The form being left occupies a known place on the canvas, so a position
    // measured inside it becomes a canvas position by shifting it there.
    final Rect leaving = collapsing ? canvas.conversation : canvas.orb;
    final double fromExtent = collapsing
        ? AgentPresenceOrb.defaultOrbExtent
        : desktopOrbExtent;
    final Rect from = origin == null
        ? Rect.fromCenter(
            center: leaving.center,
            width: fromExtent,
            height: fromExtent,
          )
        : (origin + leaving.topLeft) & Size.square(fromExtent);
    final Rect to = collapsing
        ? canvas.orb
        : Rect.fromCenter(
            center: canvas.conversation.center,
            width: AgentPresenceOrb.defaultOrbExtent,
            height: AgentPresenceOrb.defaultOrbExtent,
          );

    setState(() {
      _canvas = canvas;
      _flightFrom = from;
      _flightTo = to;
    });

    if (!collapsing) {
      // The header anchor only has a position once the conversation has been
      // laid out on the canvas, which has not happened yet.
      await _nextFrame();
      if (!mounted) {
        return;
      }
      final Rect? landing = _anchorRect();
      if (landing != null) {
        setState(() => _flightTo = landing);
      }
    }

    // Thrown rather than driven for a fixed time: the presence arrives when
    // its own weight says it does.
    //
    // Waited on until it is *home*, not until the spring has finished
    // wobbling. Those are far apart, and the window only settles once this
    // returns, so waiting for the wobble left the agent motionless at its
    // destination with nothing happening around it.
    _flight.value = 0;
    final Completer<void> home = Completer<void>();
    void watchForArrival() {
      if (!home.isCompleted && _flight.value >= 1) {
        home.complete();
      }
    }

    _flight.addListener(watchForArrival);
    final TickerFuture settling = _flight.animateWith(
      SpringSimulation(
        presenceFlightSpring,
        0,
        1,
        0,
        tolerance: presenceFlightTolerance,
      ),
    );
    // A spring that somehow never reaches its target must not hang the app.
    unawaited(
      settling.orCancel
          .whenComplete(() {
            if (!home.isCompleted) {
              home.complete();
            }
          })
          .catchError((Object _) {}),
    );
    await home.future;
    _flight.removeListener(watchForArrival);
    // Parked exactly on the destination, which is exactly where the settled
    // window puts it, so nothing is left to jump.
    _flight.stop();
    _flight.value = 1;
    if (!mounted) {
      return;
    }
    await host.endPresentationTransition(target);
    if (!mounted) {
      return;
    }
    setState(() {
      _canvas = null;
      _flightFrom = null;
      _flightTo = null;
    });
    if (!collapsing) {
      // Faded in after the window has settled rather than on the canvas: by
      // then the surface is the conversation's own size, so this costs a
      // fraction of what it would have on the canvas covering both forms.
      unawaited(_leaving.reverse());
    }
  }

  /// Builds the one orb at the size and cadence its current host wants.
  ///
  /// The properties change with the form; the orb behind them does not.
  Widget _orb({
    required double extent,
    required bool showLabel,
    bool continuousMotion = false,
  }) {
    return AgentPresenceOrb(
      key: _orbKey,
      controller: _presence,
      shaderLoader: widget.presenceShaderLoader,
      extent: extent,
      showLabel: showLabel,
      continuousMotion: continuousMotion,
    );
  }

  /// Builds the conversation, holding the orb only while it is the visible form.
  ///
  /// Exactly one host may hold the orb at a time: the conversation stays
  /// mounted while collapsed, so a header that kept claiming it would collide
  /// with the desktop surface over the same identity.
  Widget _conversation({required bool hostsOrb}) {
    return AnimatedBuilder(
      animation: _leaving,
      builder: (BuildContext context, Widget? view) {
        // Never removed from the tree, even when fully gone: the header
        // anchor the presence lands on is measured from this layout, and
        // Opacity already skips painting when there is nothing to see.
        return Opacity(
          key: const Key('conversation-visibility'),
          opacity: leavingOpacityAt(_leaving.value),
          child: Transform.scale(
            scale: leavingScaleAt(_leaving.value),
            // Rounded from inside the shrink rather than around it. Leaving
            // makes the conversation smaller than the space it occupies, so a
            // rounding applied outside is cut at a size the conversation no
            // longer is: it pulls away from its own corners and shows four
            // square ones for as long as the change of form lasts.
            child: ClipRRect(
              key: const Key('conversation-corners'),
              borderRadius: BorderRadius.circular(windowCornerRadius),
              child: view,
            ),
          ),
        );
      },
      child: ConversationView(
        screenLook: widget.composition.presentationHost == null
            ? null
            : () => widget.composition.presentationHost!.captureScreenLook(),
        key: _conversationKey,
        modelLoading: widget.composition.modelLoading,
        voiceRequests: widget.composition.voiceRequests,
        composerSeed: _composerSeed.stream,
        viewModelFactory: () => widget.composition.createConversationViewModel(
          conversationId: _openConversation,
          startFresh: _startFresh,
        ),
        onShowHistory: widget.composition.presentationHost == null
            ? null
            : () => unawaited(_showConversations()),
        voiceService: widget.composition.voiceService,
        transcriptRefiner: widget.composition.transcriptRefiner,
        transcriptShadow: widget.composition.transcriptShadow,
        protectedVocabulary: widget.composition.protectedVocabulary,
        misheard: widget.composition.misheard,
        floorControl: widget.composition.floorControl,
        unfinishedEndings: widget.composition.unfinishedEndings,
        presenceShaderLoader: widget.presenceShaderLoader,
        showVoiceEvidence: _settings.showVoiceEvidence,
        presenceController: _presence,
        presenceAnchorKey: _anchorKey,
        presenceOrb: hostsOrb
            ? _orb(
                extent: AgentPresenceOrb.defaultOrbExtent,
                // The orb already says what the agent is doing with its whole
                // body; a caption spelling it out beside the title is noise.
                // Its state stays readable to assistive tech.
                showLabel: false,
                // On the display's own cadence rather than the cheap stepped
                // idle. The stepping was chosen when this was a small ornament
                // nobody looked at; it is 5fps, and at that rate the vapour
                // visibly jerks.
                continuousMotion: true,
              )
            : null,
      ),
    );
  }

  /// Where the presence is right now, between the two forms.
  Rect _flightRect(DesktopTransitionGeometry stage) {
    final Rect? from = _flightFrom;
    final Rect? to = _flightTo;
    if (from == null || to == null) {
      return from ?? to ?? stage.orb;
    }
    return presenceFlightRect(
      from: from,
      to: to,
      t: _flight.value,
      bounds: Offset.zero & stage.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    final DesktopPresentationHost? host = widget.composition.presentationHost;
    if (host == null) {
      return _conversation(hostsOrb: true);
    }
    // The canvas of a change of form and the resting stage are the same
    // rectangle now that the window keeps one size, so one layout serves both.
    final DesktopTransitionGeometry? stage = _canvas ?? _stage;
    if (stage == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<DesktopPresentation>(
      valueListenable: host.presentation,
      builder: (BuildContext context, DesktopPresentation mode, Widget? _) {
        final bool expanded = mode == DesktopPresentation.expanded;
        final bool travelling = _canvas != null;
        return Stack(
          children: <Widget>[
            Positioned.fromRect(
              rect: stage.conversation,
              // The window's own corners are rounded by AppKit, but that mask
              // belongs to the whole stage, so the conversation drawn inside
              // it keeps its own.
              child: ClipRRect(
                borderRadius: BorderRadius.circular(windowCornerRadius),
                child: SizedBox.fromSize(
                  size: stage.conversation.size,
                  child: Stack(
                    children: <Widget>[
                      _conversation(hostsOrb: expanded && !travelling),
                      // Over the conversation rather than in a window of its
                      // own: the window is the stage and resizing it is what
                      // this app cannot afford to do.
                      if (_showingConversations && expanded && !travelling)
                        ConversationHistorySheet(
                          conversations: _conversations,
                          onOpen: _openStoredConversation,
                          onNew: _startNewConversation,
                          onDelete: (ConversationId conversationId) =>
                              unawaited(_forgetConversation(conversationId)),
                          onClose: () =>
                              setState(() => _showingConversations = false),
                          // Only reachable where there is a window to put a
                          // save panel over, which this branch already is.
                          onExport: (ConversationId conversationId) =>
                              unawaited(_exportConversation(conversationId)),
                          onSearch: (String query) =>
                              unawaited(_searchConversations(query)),
                          onRename:
                              (ConversationId conversationId, String title) =>
                                  unawaited(
                                    _renameConversation(conversationId, title),
                                  ),
                          onPin:
                              (
                                ConversationId conversationId, {
                                required bool pinned,
                              }) => unawaited(
                                _pinConversation(
                                  conversationId,
                                  pinned: pinned,
                                ),
                              ),
                        ),
                      // Before anything else it could cover: with no model
                      // the conversation behind this is a built-in preview
                      // that says the same thing every time, and letting the
                      // user talk to that first is the app pretending to
                      // work.
                      if (_settings.modelPath.isEmpty &&
                          !_lookedAround &&
                          expanded &&
                          !travelling)
                        FirstRun(
                          downloads: widget.composition.modelDownloads,
                          entry: recommendedModel,
                          onDownload: () =>
                              unawaited(_downloadModel(recommendedModel)),
                          onDismiss: () => setState(() => _lookedAround = true),
                        ),
                      if (_showingSettings && expanded && !travelling)
                        SettingsSheet(
                          agentProfile: widget.composition.agentProfile,
                          settings: _settings,
                          onChanged: (AppSettings settings) =>
                              unawaited(_changeSettings(settings)),
                          onChooseModel: () async =>
                              await host.chooseModelFile(),
                          onClose: () =>
                              setState(() => _showingSettings = false),
                          modelDownloads: widget.composition.modelDownloads,
                          catalog: widget.composition.catalog,
                          onDownloadModel: (ModelCatalogEntry entry) =>
                              unawaited(_downloadModel(entry)),
                          onUseModel: _useModel,
                          loginItem:
                              widget.composition.presentationHost?.loginItem,
                          setLaunchAtLogin: widget
                              .composition
                              .presentationHost
                              ?.setLaunchAtLogin,
                          sidecarProbe: widget.composition.sidecarProbe,
                          transcribeRecording:
                              widget.composition.voiceService == null ||
                                  widget.composition.presentationHost == null
                              ? null
                              : _transcribeRecording,
                          saveHeldTranscript:
                              widget.composition.presentationHost == null
                              ? null
                              : _saveHeldTranscript,
                          openDocument:
                              widget.composition.presentationHost == null
                              ? null
                              : _openDocument,
                          closeDocument: _closeDocument,
                          openDocumentName: widget.composition.openDocumentName,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (travelling)
              AnimatedBuilder(
                animation: _flight,
                builder: (BuildContext context, Widget? _) {
                  final Rect rect = _flightRect(stage);
                  return Positioned.fromRect(
                    rect: rect,
                    // Rendered at the size it is passing through rather than
                    // scaled, so the shader stays crisp all the way.
                    child: _orb(
                      extent: rect.width,
                      showLabel: false,
                      continuousMotion: true,
                    ),
                  );
                },
              )
            else if (!expanded)
              Positioned.fromRect(
                rect: stage.orb,
                child: DesktopOrbSurface(
                  orb: _orb(extent: desktopOrbExtent, showLabel: false),
                  presenceShaderLoader: widget.presenceShaderLoader,
                  onSummon: () =>
                      host.setPresentation(DesktopPresentation.expanded),
                  onDragBy: host.moveWindowBy,
                ),
              ),
          ],
        );
      },
    );
  }
}

ThemeData _theme(Brightness brightness, Color seed) {
  final ColorScheme colors = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    inputDecorationTheme: InputDecorationTheme(
      fillColor: colors.surfaceContainerHighest,
    ),
  );
}
