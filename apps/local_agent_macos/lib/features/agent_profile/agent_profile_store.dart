import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';

import 'agent_profile_codec.dart';

/// App-owned source of the profile used for the next model turn.
abstract interface class AgentProfileStore {
  /// Current last-known-good profile.
  AgentProfile get current;

  /// Changes when the effective profile or visible error changes.
  ValueListenable<int> get revision;

  /// Non-fatal developer configuration error, if one is active.
  String? get error;

  /// Loads the initial snapshot and starts watching when configured.
  Future<void> load();

  /// Stops watching and releases resources.
  Future<void> dispose();
}

/// A defensive profile store backed by one JSON file.
final class FileAgentProfileStore implements AgentProfileStore {
  /// Creates a store for [file].
  FileAgentProfileStore({
    required this.file,
    required this.watch,
    this.debounce = const Duration(milliseconds: 250),
  });

  /// Exact developer-authored file.
  final File file;

  /// Whether parent-directory events should reload the profile.
  final bool watch;

  /// Quiet period used to collapse editor write sequences.
  final Duration debounce;

  AgentProfile _current = AgentProfile.builtIn();
  String? _error;
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  StreamSubscription<FileSystemEvent>? _events;
  Timer? _pending;
  bool _loaded = false;
  bool _disposed = false;

  @override
  AgentProfile get current => _current;

  @override
  ValueListenable<int> get revision => _revision;

  @override
  String? get error => _error;

  @override
  Future<void> load() async {
    if (_disposed) {
      throw StateError('The agent profile store is disposed.');
    }
    await _reload();
    if (watch && !_loaded) {
      _loaded = true;
      _events = file.parent.watch().listen(_onEvent);
    }
  }

  void _onEvent(FileSystemEvent event) {
    if (_disposed || event.path != file.path) {
      return;
    }
    _pending?.cancel();
    _pending = Timer(debounce, () {
      unawaited(_reload());
    });
  }

  Future<void> _reload() async {
    if (_disposed) {
      return;
    }
    if (!await file.exists()) {
      _replace(profile: AgentProfile.builtIn(), error: null);
      return;
    }
    try {
      final Object? json = jsonDecode(await file.readAsString());
      final AgentProfileDecodeResult result = decodeAgentProfile(json);
      if (result.error != null) {
        _replace(profile: _current, error: result.error);
        return;
      }
      _replace(profile: result.profile, error: null);
    } on Object catch (exception) {
      _replace(
        profile: _current,
        error: 'Could not read agent_profile.json: ${exception.runtimeType}.',
      );
    }
  }

  void _replace({required AgentProfile profile, required String? error}) {
    if (_disposed || (profile == _current && error == _error)) {
      return;
    }
    _current = profile;
    _error = error;
    _revision.value += 1;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _pending?.cancel();
    await _events?.cancel();
    _revision.dispose();
  }
}
