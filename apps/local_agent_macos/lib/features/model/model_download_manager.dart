import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'model_catalog.dart';
import 'model_file_service.dart';

/// Where a catalog model stands on this machine.
enum ModelInstallState {
  /// Not here, or only a truncated copy of it is.
  notInstalled,

  /// On its way down right now.
  downloading,

  /// Whole and on disk.
  installed,
}

/// App-scoped download state, alive for as long as the app is.
///
/// Owned by the composition rather than any sheet: a multi-gigabyte download
/// must survive the settings being closed, and whoever reopens them finds it
/// where it truly is.
final class ModelDownloadManager extends ChangeNotifier {
  /// Creates the manager over [files].
  ModelDownloadManager({required ModelFileService files}) : this._(files);

  ModelDownloadManager._(this._files);

  final ModelFileService _files;
  final Map<String, Future<File>> _running = <String, Future<File>>{};
  final Map<String, ModelDownloadProgress> _progress =
      <String, ModelDownloadProgress>{};
  final Map<String, int> _toldPercent = <String, int>{};
  bool _disposed = false;

  /// Where [entry] stands right now.
  ModelInstallState stateOf(ModelCatalogEntry entry) {
    if (_running.containsKey(entry.id)) {
      return ModelInstallState.downloading;
    }
    return _files.isInstalled(entry)
        ? ModelInstallState.installed
        : ModelInstallState.notInstalled;
  }

  /// How far along [entry]'s download is, or null when none is running.
  ModelDownloadProgress? progressOf(ModelCatalogEntry entry) =>
      _progress[entry.id];

  /// The installed file behind [entry], or null when it is not whole.
  File? installedFileOf(ModelCatalogEntry entry) =>
      _files.isInstalled(entry) ? _files.fileFor(entry) : null;

  /// Downloads [entry], or joins the download already running for it.
  ///
  /// Completes with the installed file. A failure clears the download so it
  /// can be asked for again.
  Future<File> download(ModelCatalogEntry entry) {
    final Future<File>? running = _running[entry.id];
    if (running != null) {
      return running;
    }
    final Future<File> arriving = _download(entry);
    _running[entry.id] = arriving;
    _notify();
    return arriving;
  }

  Future<File> _download(ModelCatalogEntry entry) async {
    try {
      await for (final ModelDownloadProgress progress in _files.download(
        entry,
      )) {
        _progress[entry.id] = progress;
        // Whole percents, not network chunks: a multi-gigabyte download
        // arrives in tens of thousands of pieces, and every notification
        // rebuilds whoever is watching on the UI isolate.
        final int percent = (progress.fraction * 100).floor();
        if (_toldPercent[entry.id] != percent) {
          _toldPercent[entry.id] = percent;
          _notify();
        }
      }
      return _files.fileFor(entry);
    } finally {
      _running.remove(entry.id);
      _progress.remove(entry.id);
      _toldPercent.remove(entry.id);
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
