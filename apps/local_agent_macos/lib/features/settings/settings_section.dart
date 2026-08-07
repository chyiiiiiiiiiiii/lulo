import 'package:flutter/material.dart';

/// One titled group of settings.
final class SettingsSection extends StatelessWidget {
  /// Creates a group of settings under [title].
  const SettingsSection({
    required this.title,
    required this.children,
    this.note,
    super.key,
  });

  /// What this group of settings is about.
  final String title;

  /// A line under the title, for groups whose point is not self-evident.
  final String? note;

  /// The settings themselves.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final String? note = this.note;
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
        if (note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              note,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ...children,
      ],
    );
  }
}
