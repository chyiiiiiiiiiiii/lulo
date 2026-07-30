import 'dart:convert';
import 'dart:io';

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

  /// Returns a copy with the named choices replaced.
  AppSettings copyWith({
    bool? keepOrbOnTop,
    bool? followAcrossSpaces,
    bool? openConversationOnLaunch,
    String? modelPath,
  }) {
    return AppSettings(
      keepOrbOnTop: keepOrbOnTop ?? this.keepOrbOnTop,
      followAcrossSpaces: followAcrossSpaces ?? this.followAcrossSpaces,
      openConversationOnLaunch:
          openConversationOnLaunch ?? this.openConversationOnLaunch,
      modelPath: modelPath ?? this.modelPath,
    );
  }

  /// The form these settings are written in.
  Map<String, Object?> toJson() => <String, Object?>{
    'keepOrbOnTop': keepOrbOnTop,
    'followAcrossSpaces': followAcrossSpaces,
    'openConversationOnLaunch': openConversationOnLaunch,
    'modelPath': modelPath,
  };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.keepOrbOnTop == keepOrbOnTop &&
      other.followAcrossSpaces == followAcrossSpaces &&
      other.openConversationOnLaunch == openConversationOnLaunch &&
      other.modelPath == modelPath;

  @override
  int get hashCode => Object.hash(
    keepOrbOnTop,
    followAcrossSpaces,
    openConversationOnLaunch,
    modelPath,
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
