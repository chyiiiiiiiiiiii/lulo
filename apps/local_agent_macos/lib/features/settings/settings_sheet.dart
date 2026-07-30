import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../conversation/widgets/conversation_content_column.dart';
import '../model/model_catalog.dart';
import '../model/model_download_manager.dart';
import 'app_settings.dart';

/// The app's own settings, shown over the conversation.
///
/// Every switch here changes how the window behaves, so each one is applied as
/// it is flipped rather than behind a save button: the result is visible
/// immediately on the desktop behind this sheet.
final class SettingsSheet extends StatelessWidget {
  /// Creates the settings surface.
  const SettingsSheet({
    required this.settings,
    required this.onChanged,
    required this.onClose,
    required this.onChooseModel,
    required this.modelDownloads,
    required this.onDownloadModel,
    required this.onUseModel,
    this.catalog = modelCatalog,
    super.key,
  });

  /// Download state for the curated models, owned by the app.
  final ModelDownloadManager modelDownloads;

  /// Called with the model the user asked to fetch.
  final ValueChanged<ModelCatalogEntry> onDownloadModel;

  /// Called with the installed model the user chose to think with.
  final ValueChanged<ModelCatalogEntry> onUseModel;

  /// The models on offer, the recommended one first.
  final List<ModelCatalogEntry> catalog;

  /// Asks the user for a model file. Returns the path, or empty if they keep
  /// what they had.
  final Future<String> Function() onChooseModel;

  /// The choices currently in force.
  final AppSettings settings;

  /// Called with the whole of the new choices whenever one is changed.
  final ValueChanged<AppSettings> onChanged;

  /// Called when the user is finished.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      key: const Key('settings-sheet'),
      color: colors.surface,
      // Esc is how a Mac user backs out of anything transient. Autofocus so
      // the key lands here while the sheet is what they are looking at.
      child: Focus(
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            onClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                // The conversation's own grid: the window buttons live on the
                // line above, so the title has nothing to clear.
                padding: const EdgeInsets.fromLTRB(
                  conversationContentMargin,
                  28,
                  16,
                  8,
                ),
                child: Row(
                  children: <Widget>[
                    Text(
                      'Settings',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      key: const Key('settings-close-button'),
                      tooltip: 'Close settings',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ConversationContentColumn(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: conversationContentMargin,
                    ),
                    children: <Widget>[
                      _Section(
                        title: 'On the desktop',
                        children: <Widget>[
                          SwitchListTile(
                            key: const Key('setting-keep-orb-on-top'),
                            value: settings.keepOrbOnTop,
                            title: const Text(
                              'Keep the orb above other windows',
                            ),
                            subtitle: const Text(
                              'Off puts it in the normal window order, where other '
                              'windows can cover it.',
                            ),
                            onChanged: (bool value) => onChanged(
                              settings.copyWith(keepOrbOnTop: value),
                            ),
                          ),
                          SwitchListTile(
                            key: const Key('setting-follow-across-spaces'),
                            value: settings.followAcrossSpaces,
                            title: const Text('Follow me between Spaces'),
                            subtitle: const Text(
                              'Off leaves the orb on the Space it was opened in.',
                            ),
                            onChanged: (bool value) => onChanged(
                              settings.copyWith(followAcrossSpaces: value),
                            ),
                          ),
                        ],
                      ),
                      _Section(
                        title: 'When it starts',
                        children: <Widget>[
                          SwitchListTile(
                            key: const Key('setting-open-on-launch'),
                            value: settings.openConversationOnLaunch,
                            title: const Text(
                              'Open the conversation on launch',
                            ),
                            subtitle: const Text(
                              'Off rests as an orb until you summon it.',
                            ),
                            onChanged: (bool value) => onChanged(
                              settings.copyWith(
                                openConversationOnLaunch: value,
                              ),
                            ),
                          ),
                        ],
                      ),
                      _Section(
                        title: 'The model it thinks with',
                        children: <Widget>[
                          AnimatedBuilder(
                            animation: modelDownloads,
                            builder: (BuildContext context, Widget? _) =>
                                Column(
                                  children: <Widget>[
                                    for (final ModelCatalogEntry entry
                                        in catalog)
                                      _ModelRow(
                                        entry: entry,
                                        downloads: modelDownloads,
                                        activePath: settings.modelPath,
                                        onDownload: () =>
                                            onDownloadModel(entry),
                                        onUse: () => onUseModel(entry),
                                      ),
                                  ],
                                ),
                          ),
                          ListTile(
                            key: const Key('setting-model-path'),
                            title: Text(
                              settings.modelPath.isEmpty
                                  ? 'No model chosen'
                                  : settings.modelPath.split('/').last,
                            ),
                            subtitle: Text(
                              settings.modelPath.isEmpty
                                  ? 'Lulo is answering from its built-in preview, '
                                        'which says the same thing every time.'
                                  : 'Loaded now. Choosing another takes a few '
                                        'seconds to swap.',
                            ),
                            trailing: FilledButton.tonal(
                              key: const Key('setting-choose-model'),
                              onPressed: () async {
                                final String chosen = await onChooseModel();
                                if (chosen.isNotEmpty) {
                                  onChanged(
                                    settings.copyWith(modelPath: chosen),
                                  );
                                }
                              },
                              child: const Text('Choose…'),
                            ),
                          ),
                        ],
                      ),
                      _Section(
                        title: 'Summoning',
                        children: const <Widget>[
                          ListTile(
                            title: Text('Show or hide the conversation'),
                            subtitle: Text('Anywhere on the Mac.'),
                            trailing: Text('⌘⇧Space'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

/// One curated model: what it is, where it stands, and the one next step.
final class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.entry,
    required this.downloads,
    required this.activePath,
    required this.onDownload,
    required this.onUse,
  });

  final ModelCatalogEntry entry;
  final ModelDownloadManager downloads;
  final String activePath;
  final VoidCallback onDownload;
  final VoidCallback onUse;

  String get _sizeLabel =>
      '${(entry.sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';

  @override
  Widget build(BuildContext context) {
    final ModelInstallState state = downloads.stateOf(entry);
    if (state == ModelInstallState.downloading) {
      return ListTile(
        title: Text(entry.name),
        subtitle: LinearProgressIndicator(
          key: Key('model-progress-${entry.id}'),
          value: downloads.progressOf(entry)?.fraction,
        ),
      );
    }
    final bool active =
        state == ModelInstallState.installed &&
        activePath == downloads.installedFileOf(entry)?.path;
    return ListTile(
      title: Text(
        entry.recommended ? '${entry.name} — recommended' : entry.name,
      ),
      subtitle: Text('${entry.description} $_sizeLabel.'),
      trailing: active
          ? Icon(
              Icons.check_rounded,
              key: Key('model-active-${entry.id}'),
              color: Theme.of(context).colorScheme.primary,
            )
          : state == ModelInstallState.installed
          ? FilledButton.tonal(
              key: Key('model-use-${entry.id}'),
              onPressed: onUse,
              child: const Text('Use'),
            )
          : FilledButton.tonal(
              key: Key('model-download-${entry.id}'),
              onPressed: onDownload,
              child: const Text('Download'),
            ),
    );
  }
}
