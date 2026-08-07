import 'dart:async';

import 'package:agent_core/agent_core.dart';

import 'package:flutter/material.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';

/// A window host the tests hold in their hand instead of AppKit.
final class FakePresentationHost implements DesktopPresentationHost {
  @override
  final ValueNotifier<DesktopPresentation> presentation =
      ValueNotifier<DesktopPresentation>(DesktopPresentation.orb);

  @override
  Future<void> setPresentation(DesktopPresentation mode) async {
    presentation.value = mode;
  }

  /// Text a Services menu is pretending to have sent.
  final StreamController<String> serviceTextController =
      StreamController<String>.broadcast();

  @override
  Stream<String> get serviceText => serviceTextController.stream;

  /// What the system is pretending to say about starting at login.
  DesktopLoginItem loginItemValue = DesktopLoginItem.off;

  /// Every value passed to [setLaunchAtLogin], in order.
  final List<bool> launchAtLoginRequests = <bool>[];

  @override
  Future<DesktopLoginItem> loginItem() async => loginItemValue;

  @override
  Future<DesktopLoginItem> setLaunchAtLogin({required bool enabled}) async {
    launchAtLoginRequests.add(enabled);
    // Only moves if the fake was not told the system would refuse, so a test
    // can pin what the app shows when macOS does not do as it is asked.
    if (loginItemValue != DesktopLoginItem.unavailable &&
        loginItemValue != DesktopLoginItem.needsApproval) {
      loginItemValue = enabled ? DesktopLoginItem.on : DesktopLoginItem.off;
    }
    return loginItemValue;
  }

  /// Deltas passed to [moveWindowBy], in order.
  final List<Offset> moves = <Offset>[];

  @override
  Future<void> moveWindowBy(Offset delta) async {
    moves.add(delta);
  }

  final StreamController<DesktopPresentation> _requests =
      StreamController<DesktopPresentation>.broadcast();

  @override
  Stream<DesktopPresentation> get presentationRequests => _requests.stream;

  /// Stands in for the hotkey or the menu bar asking for a change of form.
  void requestPresentation(DesktopPresentation target) {
    _requests.add(target);
  }

  final StreamController<DesktopTransitionGeometry> _geometryChanges =
      StreamController<DesktopTransitionGeometry>.broadcast();

  @override
  Stream<DesktopTransitionGeometry> get geometryChanges =>
      _geometryChanges.stream;

  /// Stands in for the user resizing the window.
  void changeGeometry(DesktopTransitionGeometry stage) {
    geometry = stage;
    _geometryChanges.add(stage);
  }

  /// Releases the request stream.
  Future<void> dispose() async {
    await _requests.close();
    await _settings.close();
    await _geometryChanges.close();
    await menuConversations.close();
    await menuVoice.close();
  }

  /// A canvas holding a centred conversation and an orb in the lower corner.
  DesktopTransitionGeometry geometry = const DesktopTransitionGeometry(
    size: Size(1268, 828),
    conversation: Rect.fromLTWH(0, 0, 720, 560),
    orb: Rect.fromLTWH(1100, 660, 148, 148),
  );

  /// Targets passed to [beginPresentationTransition], in order.
  final List<DesktopPresentation> begunTransitions = <DesktopPresentation>[];

  /// Modes passed to [endPresentationTransition], in order.
  final List<DesktopPresentation> endedTransitions = <DesktopPresentation>[];

  final StreamController<void> _settings = StreamController<void>.broadcast();

  @override
  Stream<void> get settingsRequests => _settings.stream;

  /// Stands in for the menu bar asking for settings.
  void requestSettings() => _settings.add(null);

  /// Choices the app has pushed to the host, in order.
  final List<(bool, bool)> windowBehaviours = <(bool, bool)>[];

  /// What the chooser answers with in tests.
  String chosenModelFile = '';

  @override
  Future<String> chooseModelFile() async => chosenModelFile;

  /// Where the fake was asked to save, and what.
  final List<({String suggestedName, String contents})> savedFiles =
      <({String suggestedName, String contents})>[];

  /// What the fake save panel answers with; empty means the user backed out.
  String savePath = '/tmp/fake-export.md';

  @override
  Future<String> saveTextFile({
    required String suggestedName,
    required String contents,
  }) async {
    savedFiles.add((suggestedName: suggestedName, contents: contents));
    return savePath;
  }

  /// Conversations a test offers through the status-bar menu.
  final StreamController<ConversationId> menuConversations =
      StreamController<ConversationId>.broadcast();

  /// Voice requests a test makes from the status-bar menu.
  final StreamController<void> menuVoice = StreamController<void>.broadcast();

  /// Every state the menu bar has been told to show, newest last.
  final List<FakeMenuBarState> menuBarStates = <FakeMenuBarState>[];

  @override
  Stream<ConversationId> get menuConversationRequests =>
      menuConversations.stream;

  @override
  Stream<void> get menuVoiceRequests => menuVoice.stream;

  @override
  Future<void> setMenuBarState({
    required List<({ConversationId id, String title})> conversations,
    required String modelName,
    required DesktopAgentActivity activity,
    required bool canStartVoice,
    required DesktopMenuBarLabels labels,
  }) async {
    menuBarStates.add(
      FakeMenuBarState(
        conversations: conversations,
        modelName: modelName,
        activity: activity,
        canStartVoice: canStartVoice,
        labels: labels,
      ),
    );
  }

  @override
  Future<void> setWindowBehaviour({
    required bool keepOrbOnTop,
    required bool followAcrossSpaces,
  }) async {
    windowBehaviours.add((keepOrbOnTop, followAcrossSpaces));
  }

  @override
  Future<DesktopTransitionGeometry> presentationGeometry() async => geometry;

  @override
  Future<DesktopTransitionGeometry> beginPresentationTransition(
    DesktopPresentation target,
  ) async {
    begunTransitions.add(target);
    return geometry;
  }

  @override
  Future<void> endPresentationTransition(DesktopPresentation mode) async {
    endedTransitions.add(mode);
    presentation.value = mode;
  }
}

/// A shader loader that refuses, for tests that never draw the presence.
Future<Never> failShaderLoad() async {
  throw UnsupportedError('Runtime shader rendering is outside this test.');
}

/// One state the status-bar menu was told to show.
final class FakeMenuBarState {
  /// Records one push to the menu bar.
  const FakeMenuBarState({
    required this.conversations,
    required this.modelName,
    required this.activity,
    required this.canStartVoice,
    required this.labels,
  });

  /// The words it was told to show.
  final DesktopMenuBarLabels labels;

  /// The conversations it was told to list.
  final List<({ConversationId id, String title})> conversations;

  /// What it was told the agent thinks with.
  final String modelName;

  /// What it was told the agent is doing.
  final DesktopAgentActivity activity;

  /// Whether it was told voice can be started.
  final bool canStartVoice;
}
