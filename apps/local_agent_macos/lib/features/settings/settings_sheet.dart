import 'package:flutter/material.dart';

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
    super.key,
  });

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
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(78, 20, 16, 8),
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
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: <Widget>[
                  _Section(
                    title: 'On the desktop',
                    children: <Widget>[
                      SwitchListTile(
                        key: const Key('setting-keep-orb-on-top'),
                        value: settings.keepOrbOnTop,
                        title: const Text('Keep the orb above other windows'),
                        subtitle: const Text(
                          'Off puts it in the normal window order, where other '
                          'windows can cover it.',
                        ),
                        onChanged: (bool value) =>
                            onChanged(settings.copyWith(keepOrbOnTop: value)),
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
                        title: const Text('Open the conversation on launch'),
                        subtitle: const Text(
                          'Off rests as an orb until you summon it.',
                        ),
                        onChanged: (bool value) => onChanged(
                          settings.copyWith(openConversationOnLaunch: value),
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
          ],
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
