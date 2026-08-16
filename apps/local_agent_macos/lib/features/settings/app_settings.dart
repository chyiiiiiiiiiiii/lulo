import 'dart:convert';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';

/// What the user has chosen about how the agent sits on their desktop.
///
/// Every field here is honoured by the window itself. Nothing is stored that
/// the app cannot act on.
@immutable
final class AppSettings {
  /// Creates the settings, defaulting to a presence that rests on the desktop.
  const AppSettings({
    this.keepOrbOnTop = true,
    this.followAcrossSpaces = true,
    this.openConversationOnLaunch = false,
    this.modelPath = '',
    this.ttsVoice = 'ryan',
    this.showVoiceEvidence = false,
    this.answerStyle = AnswerStyle.balanced,
    this.shareFrontmostApp = false,
  });

  /// Reads settings written by [toJson], ignoring anything unrecognised.
  ///
  /// A field written by a later version, or one that has been removed, must
  /// not stop the rest from being read.
  factory AppSettings.fromJson(Map<String, Object?> json) {
    const AppSettings defaults = AppSettings();
    return AppSettings(
      keepOrbOnTop: _boolOr(json['keepOrbOnTop'], defaults.keepOrbOnTop),
      followAcrossSpaces: _boolOr(
        json['followAcrossSpaces'],
        defaults.followAcrossSpaces,
      ),
      openConversationOnLaunch: _boolOr(
        json['openConversationOnLaunch'],
        defaults.openConversationOnLaunch,
      ),
      modelPath: json['modelPath'] is String
          ? json['modelPath']! as String
          : defaults.modelPath,
      ttsVoice: json['ttsVoice'] is String
          ? json['ttsVoice']! as String
          : defaults.ttsVoice,
      showVoiceEvidence: _boolOr(
        json['showVoiceEvidence'],
        defaults.showVoiceEvidence,
      ),
      answerStyle:
          AnswerStyle.values.asNameMap()[json['answerStyle']] ??
          defaults.answerStyle,
      shareFrontmostApp: _boolOr(
        json['shareFrontmostApp'],
        defaults.shareFrontmostApp,
      ),
    );
  }

  /// Whether the resting orb floats above other windows.
  final bool keepOrbOnTop;

  /// Whether the resting orb follows the user between Spaces.
  final bool followAcrossSpaces;

  /// Whether launching opens the conversation instead of resting as an orb.
  final bool openConversationOnLaunch;

  /// The LiteRT-LM file the agent thinks with, or empty for the preview.
  ///
  /// Chosen here rather than fixed when the app is built, so changing model
  /// does not mean compiling a new app.
  final String modelPath;

  /// Who speaks the answers aloud, by the resident synthesizer's voice name.
  final String ttsVoice;

  /// How far the model may roam when it answers.
  ///
  /// Applied to the next question rather than by reloading the model: the
  /// sampler travels in the request the host already receives.
  final AnswerStyle answerStyle;

  /// Whether the conversation shows why the agent took or yielded the floor.
  ///
  /// Off by default: it is an instrument for tuning turn-taking, not
  /// something to read while having a conversation.
  final bool showVoiceEvidence;

  /// Whether each question carries the name of the app the user is in.
  ///
  /// Off by default, because it is information leaving the user's desktop
  /// for the model's context and that is theirs to switch on. The name of
  /// the frontmost app is all this shares — never window titles or
  /// contents, which macOS meters behind permissions this app does not
  /// hold. See `docs/decisions/the-companion-that-watches.md`.
  final bool shareFrontmostApp;

  /// Returns a copy with the named choices replaced.
  AppSettings copyWith({
    bool? keepOrbOnTop,
    bool? followAcrossSpaces,
    bool? openConversationOnLaunch,
    String? modelPath,
    String? ttsVoice,
    bool? showVoiceEvidence,
    AnswerStyle? answerStyle,
    bool? shareFrontmostApp,
  }) {
    return AppSettings(
      keepOrbOnTop: keepOrbOnTop ?? this.keepOrbOnTop,
      followAcrossSpaces: followAcrossSpaces ?? this.followAcrossSpaces,
      openConversationOnLaunch:
          openConversationOnLaunch ?? this.openConversationOnLaunch,
      modelPath: modelPath ?? this.modelPath,
      ttsVoice: ttsVoice ?? this.ttsVoice,
      showVoiceEvidence: showVoiceEvidence ?? this.showVoiceEvidence,
      answerStyle: answerStyle ?? this.answerStyle,
      shareFrontmostApp: shareFrontmostApp ?? this.shareFrontmostApp,
    );
  }

  /// The form these settings are written in.
  Map<String, Object?> toJson() => <String, Object?>{
    'keepOrbOnTop': keepOrbOnTop,
    'followAcrossSpaces': followAcrossSpaces,
    'openConversationOnLaunch': openConversationOnLaunch,
    'modelPath': modelPath,
    'ttsVoice': ttsVoice,
    'showVoiceEvidence': showVoiceEvidence,
    'answerStyle': answerStyle.name,
    'shareFrontmostApp': shareFrontmostApp,
  };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.keepOrbOnTop == keepOrbOnTop &&
      other.followAcrossSpaces == followAcrossSpaces &&
      other.openConversationOnLaunch == openConversationOnLaunch &&
      other.modelPath == modelPath &&
      other.ttsVoice == ttsVoice &&
      other.showVoiceEvidence == showVoiceEvidence &&
      other.answerStyle == answerStyle &&
      other.shareFrontmostApp == shareFrontmostApp;

  @override
  int get hashCode => Object.hash(
    keepOrbOnTop,
    followAcrossSpaces,
    openConversationOnLaunch,
    modelPath,
    ttsVoice,
    showVoiceEvidence,
    answerStyle,
    shareFrontmostApp,
  );

  @override
  String toString() =>
      'AppSettings(keepOrbOnTop: $keepOrbOnTop, followAcrossSpaces: '
      '$followAcrossSpaces, openConversationOnLaunch: '
      '$openConversationOnLaunch, modelPath: $modelPath)';
}

/// Where the user's choices are kept between runs.
abstract interface class SettingsStore {
  /// Reads the stored choices, or the defaults when there are none.
  Future<AppSettings> load();

  /// Writes [settings] so the next run starts from them.
  Future<void> save(AppSettings settings);
}

/// Keeps settings in a file beside the rest of the app's own data.
final class FileSettingsStore implements SettingsStore {
  /// Creates a store writing into [directory].
  FileSettingsStore({required this.directory});

  /// Where the settings file is kept.
  final Directory directory;

  /// The file the choices are written to.
  File get file => File('${directory.path}/settings.json');

  @override
  Future<AppSettings> load() async {
    // Settings are a convenience. Losing them costs the user their
    // preferences; failing to start costs them their agent, so anything
    // unreadable is treated as nothing having been chosen yet.
    try {
      if (!file.existsSync()) {
        return const AppSettings();
      }
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) {
        return const AppSettings();
      }
      return AppSettings.fromJson(decoded);
    } on Object {
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(settings.toJson()));
  }
}

/// Keeps settings only for as long as the app runs, for tests.
final class InMemorySettingsStore implements SettingsStore {
  /// Creates a store starting from [settings].
  InMemorySettingsStore([this._settings = const AppSettings()]);

  AppSettings _settings;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;
}

bool _boolOr(Object? value, bool fallback) => value is bool ? value : fallback;
