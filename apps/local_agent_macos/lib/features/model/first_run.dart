import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../conversation/widgets/conversation_content_column.dart';
import 'model_catalog.dart';
import 'model_download_manager.dart';

/// The first launch, which has exactly one thing to do.
///
/// Without a model Lulo answers from a built-in preview that says the same
/// thing every time, and the way to fix that was three sections down a
/// settings sheet the user had no reason to open. An agent that looks like it
/// is working and is not is worse than one that says what it needs.
final class FirstRun extends StatelessWidget {
  /// Creates the first-launch surface for [entry].
  const FirstRun({
    required this.downloads,
    required this.entry,
    required this.onDownload,
    required this.onDismiss,
    super.key,
  });

  /// Where the download's state is read from.
  final ModelDownloadManager downloads;

  /// The model being offered.
  final ModelCatalogEntry entry;

  /// Starts fetching [entry].
  final VoidCallback onDownload;

  /// Puts this away without a model, so the user can look around.
  final VoidCallback onDismiss;

  String get _size =>
      '${(entry.sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final AppLocalizations words = AppLocalizations.of(context);
    return Material(
      key: const Key('first-run'),
      color: colors.surface,
      child: SafeArea(
        child: ConversationContentColumn(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: conversationContentMargin,
                vertical: 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 30,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(words.firstRunTitle, style: text.headlineSmall),
                  const SizedBox(height: 10),
                  Text(
                    words.firstRunBody,
                    style: text.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 26),
                  _Offer(
                    downloads: downloads,
                    entry: entry,
                    size: _size,
                    onDownload: onDownload,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    words.firstRunMicNote,
                    style: text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    key: const Key('first-run-dismiss'),
                    onPressed: onDismiss,
                    child: Text(words.firstRunDismiss),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The model on offer and the one next step for it.
final class _Offer extends StatelessWidget {
  const _Offer({
    required this.downloads,
    required this.entry,
    required this.size,
    required this.onDownload,
  });

  final ModelDownloadManager downloads;
  final ModelCatalogEntry entry;
  final String size;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final AppLocalizations words = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: downloads,
      builder: (BuildContext context, Widget? _) {
        final ModelInstallState state = downloads.stateOf(entry);
        final String? failure = downloads.failureOf(entry);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(entry.name, style: text.titleSmall),
              const SizedBox(height: 4),
              Text(
                words.modelSummary(entry.description(words), size),
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              if (state == ModelInstallState.downloading) ...<Widget>[
                LinearProgressIndicator(
                  key: const Key('first-run-progress'),
                  value: downloads.progressOf(entry)?.fraction,
                ),
                const SizedBox(height: 8),
                Text(
                  words.firstRunDownloading,
                  style: text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ] else ...<Widget>[
                if (failure != null) ...<Widget>[
                  Text(
                    words.downloadFailed(failure),
                    key: const Key('first-run-failure'),
                    style: text.bodySmall?.copyWith(color: colors.error),
                  ),
                  const SizedBox(height: 10),
                ],
                FilledButton(
                  key: const Key('first-run-download'),
                  onPressed: onDownload,
                  child: Text(
                    failure == null
                        ? words.firstRunDownload
                        : words.firstRunRetry,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
