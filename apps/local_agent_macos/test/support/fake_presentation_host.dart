import 'dart:async';

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
