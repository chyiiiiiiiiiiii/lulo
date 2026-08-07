import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../platform/desktop_host_service.dart';
import '../agent_profile/agent_profile_store.dart';
import '../conversation/widgets/conversation_content_column.dart';
import '../model/model_catalog.dart';
import '../model/model_download_manager.dart';
import '../sidecar/sidecar_health.dart';
import '../voice/tts_voices.dart';
import 'agent_profile_settings.dart';
import 'app_settings.dart';
import 'settings_section.dart';

/// The app's own settings, shown over the conversation.
///
/// Every switch here changes how the window behaves, so each one is applied as
/// it is flipped rather than behind a save button: the result is visible
/// immediately on the desktop behind this sheet.
final class SettingsSheet extends StatelessWidget {
  /// Creates the settings surface.
  const SettingsSheet({
    required this.agentProfile,
    required this.settings,
    required this.onChanged,
    required this.onClose,
    required this.onChooseModel,
    required this.modelDownloads,
    required this.onDownloadModel,
    required this.onUseModel,
    this.loginItem,
    this.setLaunchAtLogin,
    this.sidecarProbe,
    this.transcribeRecording,
    this.catalog = modelCatalog,
    super.key,
  });

  /// Who Lulo is and how it talks, read and written in place.
  final AgentProfileStore agentProfile;

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

  /// Whether macOS currently starts the app at login, or null on a surface
  /// with no window host to ask — a test, or the app before it has one.
  ///
  /// Asked rather than stored: the registration is the system's and the user
  /// can revoke it in System Settings while the app is not running, so a
  /// remembered answer would eventually be a wrong one.
  final Future<DesktopLoginItem> Function()? loginItem;

  /// Asks macOS to start the app at login, or to stop, and reports what
  /// actually resulted.
  final Future<DesktopLoginItem> Function({required bool enabled})?
  setLaunchAtLogin;

  /// How to ask whether the two helper processes are running, or null on a
  /// surface that should not ask.
  ///
  /// Nullable for the same reason [loginItem] is, and for one more: the
  /// probe opens a real socket with a real timeout, and a widget test that
  /// merely renders this sheet must not be left holding a pending timer for
  /// a question it never asked.
  final SidecarHealthProbe? sidecarProbe;

  /// Picks a recording, writes it out, and saves the text — or null on a
  /// surface with no recogniser behind it.
  final Future<String?> Function()? transcribeRecording;

  /// Called when the user is finished.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final AppLocalizations words = AppLocalizations.of(context);
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
                      words.settingsTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      key: const Key('settings-close-button'),
                      tooltip: words.closeSettings,
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
                      SettingsSection(
                        title: words.sectionDesktop,
                        children: <Widget>[
                          SwitchListTile(
                            key: const Key('setting-keep-orb-on-top'),
                            value: settings.keepOrbOnTop,
                            title: Text(words.keepOrbOnTop),
                            subtitle: Text(words.keepOrbOnTopNote),
                            onChanged: (bool value) => onChanged(
                              settings.copyWith(keepOrbOnTop: value),
                            ),
                          ),
                          SwitchListTile(
                            key: const Key('setting-follow-across-spaces'),
                            value: settings.followAcrossSpaces,
                            title: Text(words.followAcrossSpaces),
                            subtitle: Text(words.followAcrossSpacesNote),
                            onChanged: (bool value) => onChanged(
                              settings.copyWith(followAcrossSpaces: value),
                            ),
                          ),
                        ],
                      ),
                      if (transcribeRecording != null)
                        _TranscribeSection(run: transcribeRecording!),
                      if (sidecarProbe != null)
                        SidecarSection(probe: sidecarProbe!),
                      SettingsSection(
                        title: words.sectionStart,
                        children: <Widget>[
                          if (loginItem != null && setLaunchAtLogin != null)
                            _LaunchAtLoginSwitch(
                              read: loginItem!,
                              write: setLaunchAtLogin!,
                            ),
                          SwitchListTile(
                            key: const Key('setting-open-on-launch'),
                            value: settings.openConversationOnLaunch,
                            title: Text(words.openOnLaunch),
                            subtitle: Text(words.openOnLaunchNote),
                            onChanged: (bool value) => onChanged(
                              settings.copyWith(
                                openConversationOnLaunch: value,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SettingsSection(
                        title: words.sectionModel,
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
                                  ? words.noModelChosen
                                  : settings.modelPath.split('/').last,
                            ),
                            subtitle: Text(
                              settings.modelPath.isEmpty
                                  ? words.previewNote
                                  : words.modelLoadedNote,
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
                              child: Text(words.chooseModel),
                            ),
                          ),
                        ],
                      ),
                      SettingsSection(
                        title: words.sectionVoice,
                        children: <Widget>[
                          ListTile(
                            key: const Key('setting-tts-voice'),
                            title: Text(words.voiceLabel),
                            subtitle: Text(words.voiceNote),
                            trailing: DropdownButton<String>(
                              key: const Key('setting-tts-voice-dropdown'),
                              value: ttsVoices.contains(settings.ttsVoice)
                                  ? settings.ttsVoice
                                  : ttsVoices.first,
                              items: <DropdownMenuItem<String>>[
                                for (final String voice in ttsVoices)
                                  DropdownMenuItem<String>(
                                    value: voice,
                                    child: Text(voice),
                                  ),
                              ],
                              onChanged: (String? voice) {
                                if (voice != null) {
                                  onChanged(settings.copyWith(ttsVoice: voice));
                                }
                              },
                            ),
                            onTap: null,
                          ),
                        ],
                      ),
                      SettingsSection(
                        title: words.sectionAnswerStyle,
                        note: words.answerStyleNote,
                        children: <Widget>[
                          _AnswerStyleChoice(
                            value: settings.answerStyle,
                            onChanged: (AnswerStyle style) => onChanged(
                              settings.copyWith(answerStyle: style),
                            ),
                          ),
                        ],
                      ),
                      SettingsSection(
                        title: words.sectionHearing,
                        children: <Widget>[
                          ListTile(
                            key: const Key('setting-hearing-hold'),
                            title: Text(words.hearingHoldTitle),
                            subtitle: Text(words.hearingHoldNote),
                          ),
                          ListTile(
                            key: const Key('setting-hearing-duplex'),
                            title: Text(words.hearingDuplexTitle),
                            subtitle: Text(words.hearingDuplexNote),
                          ),
                        ],
                      ),
                      AgentProfileSettings(store: agentProfile),
                      SettingsSection(
                        title: words.sectionTakingTurns,
                        children: <Widget>[
                          SwitchListTile(
                            key: const Key('setting-show-voice-evidence'),
                            value: settings.showVoiceEvidence,
                            title: Text(words.showVoiceEvidence),
                            subtitle: Text(words.showVoiceEvidenceNote),
                            onChanged: (bool value) => onChanged(
                              settings.copyWith(showVoiceEvidence: value),
                            ),
                          ),
                        ],
                      ),
                      SettingsSection(
                        title: words.sectionSummoning,
                        children: <Widget>[
                          ListTile(
                            title: Text(words.showHideConversation),
                            subtitle: Text(words.anywhereOnMac),
                            trailing: const Text('⌘⇧Space'),
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
    final AppLocalizations words = AppLocalizations.of(context);
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
    final String? failure = downloads.failureOf(entry);
    return ListTile(
      title: Text(
        entry.recommended ? words.modelRecommended(entry.name) : entry.name,
      ),
      subtitle: failure == null
          ? Text(words.modelSummary(entry.description(words), _sizeLabel))
          : Text(
              words.downloadFailed(failure),
              key: Key('model-failure-${entry.id}'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
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
              child: Text(words.useModel),
            )
          : FilledButton.tonal(
              key: Key('model-download-${entry.id}'),
              onPressed: onDownload,
              child: Text(
                failure == null ? words.downloadModel : words.retryDownload,
              ),
            ),
    );
  }
}

/// How far the model may roam, as three named choices.
///
/// Named rather than numbered: temperature is a number nobody outside the
/// model has the information to choose, and the two dials behind these move
/// together because they are two halves of one decision.
final class _AnswerStyleChoice extends StatelessWidget {
  const _AnswerStyleChoice({required this.value, required this.onChanged});

  final AnswerStyle value;
  final ValueChanged<AnswerStyle> onChanged;

  static ({String label, String note}) _describe(
    AppLocalizations words,
    AnswerStyle style,
  ) => switch (style) {
    AnswerStyle.steady => (
      label: words.answerStyleSteady,
      note: words.answerStyleSteadyNote,
    ),
    AnswerStyle.balanced => (
      label: words.answerStyleBalanced,
      note: words.answerStyleBalancedNote,
    ),
    AnswerStyle.inventive => (
      label: words.answerStyleInventive,
      note: words.answerStyleInventiveNote,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations words = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 6,
            children: <Widget>[
              for (final AnswerStyle style in AnswerStyle.values)
                ChoiceChip(
                  key: Key('setting-answer-style-${style.name}'),
                  label: Text(_describe(words, style).label),
                  selected: style == value,
                  onSelected: (bool _) => onChanged(style),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _describe(words, value).note,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A switch that shows what macOS says, not what it was asked for.
///
/// The registration lives in the system, so this reads it rather than
/// keeping a copy: the user can revoke it in System Settings while the app
/// is not running, and a remembered answer would then be wrong with no way
/// to notice. It is read again whenever the app comes back to the front,
/// because the one thing this switch can tell the user to do is go to
/// System Settings, and coming back to a sheet still showing the old answer
/// is the same as the switch not working.
///
/// macOS answers with more than yes and no, and every other answer is shown
/// rather than flattened into off. A switch that flips back a second later
/// with nothing said is indistinguishable from a broken app.
final class _LaunchAtLoginSwitch extends StatefulWidget {
  const _LaunchAtLoginSwitch({required this.read, required this.write});

  final Future<DesktopLoginItem> Function() read;
  final Future<DesktopLoginItem> Function({required bool enabled}) write;

  @override
  State<_LaunchAtLoginSwitch> createState() => _LaunchAtLoginSwitchState();
}

final class _LaunchAtLoginSwitchState extends State<_LaunchAtLoginSwitch>
    with WidgetsBindingObserver {
  DesktopLoginItem? _status;
  bool _asking = false;
  bool _unreachable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from System Settings, most likely — which is where this switch
    // sends the user when macOS is holding the registration.
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    await _ask(() => widget.read());
  }

  Future<void> _ask(Future<DesktopLoginItem> Function() call) async {
    try {
      final DesktopLoginItem status = await call();
      if (mounted) {
        setState(() {
          _status = status;
          _unreachable = false;
        });
      }
    } on Object {
      // The host can be gone, or the channel can fail. Swallowing it left
      // the switch invisible forever with nothing said; the row stays and
      // says it could not ask.
      if (mounted) {
        setState(() => _unreachable = true);
      }
    }
  }

  Future<void> _set({required bool enabled}) async {
    if (_asking) {
      // Two fast taps otherwise race, and the loser's answer can land last.
      return;
    }
    setState(() => _asking = true);
    await _ask(() => widget.write(enabled: enabled));
    if (mounted) {
      setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations words = AppLocalizations.of(context);
    final DesktopLoginItem? status = _status;
    if (status == null && !_unreachable) {
      // Nothing is drawn until the system has answered. A switch shown at a
      // guess would be seen in the wrong position and then jump.
      return const SizedBox.shrink();
    }
    final String? caveat = _unreachable
        ? words.launchAtLoginFailed
        : switch (status!) {
            DesktopLoginItem.needsApproval => words.launchAtLoginNeedsApproval,
            DesktopLoginItem.refused => words.launchAtLoginRefused,
            DesktopLoginItem.unavailable => words.launchAtLoginUnavailable,
            DesktopLoginItem.on || DesktopLoginItem.off => null,
          };
    // Nothing the user does here changes a refusal or an old macOS, so the
    // switch is left unusable rather than inviting a tap that does nothing.
    // The row stays visible either way: the setting exists, and why it is
    // out of reach is the useful part.
    final bool settable =
        !_unreachable &&
        status != DesktopLoginItem.refused &&
        status != DesktopLoginItem.unavailable;
    // A held registration reads as on, because that is what it is: macOS has
    // it and is waiting for the user, and the subtitle is what stops that
    // being a false promise. Showing it off instead makes the only way out
    // of the state a tap asking to register a second time, which macOS
    // answers with `kSMErrorAlreadyRegistered` — nothing moves, in either
    // direction, forever.
    final bool asked =
        status == DesktopLoginItem.on ||
        status == DesktopLoginItem.needsApproval;
    return SwitchListTile(
      key: const Key('setting-launch-at-login'),
      value: asked,
      title: Text(words.launchAtLogin),
      subtitle: Text(caveat ?? words.launchAtLoginNote),
      // Asked for by what it would become rather than by the switch's own
      // position, so the two can never disagree about a pending state.
      onChanged: settable ? (bool _) => unawaited(_set(enabled: !asked)) : null,
    );
  }
}

/// Whether the two helper processes the voice path needs are running.
///
/// Neither is in this repository, both are started by hand, and both fail
/// silently — without the voice the agent hears, thinks, writes, and stays
/// quiet, with nothing on screen saying why. This is the one place that
/// says so.
///
/// It reports and does not offer to fix. Lulo is sandboxed and cannot spawn
/// a subprocess, so a button here would be a button that does nothing, which
/// is worse than a sentence that tells the truth.
final class SidecarSection extends StatefulWidget {
  /// Creates the section over [probe].
  const SidecarSection({required this.probe, super.key});

  /// How to ask. Injected so a test can state what is listening rather than
  /// opening a socket.
  final SidecarHealthProbe probe;

  @override
  State<SidecarSection> createState() => _SidecarSectionState();
}

final class _SidecarSectionState extends State<SidecarSection> {
  SidecarHealth? _health;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      final SidecarHealth health = await widget.probe.check();
      if (mounted) {
        setState(() => _health = health);
      }
    } on Object {
      // A probe that itself failed says nothing rather than accusing a
      // process that may be perfectly fine.
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations words = AppLocalizations.of(context);
    final SidecarHealth? health = _health;
    if (health == null) {
      // Nothing until the answer is in. Guessing would show a warning and
      // then take it back, which reads worse than a beat of nothing.
      return const SizedBox.shrink();
    }
    return SettingsSection(
      key: const Key('setting-sidecars'),
      title: words.sidecarSection,
      children: <Widget>[
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          // Asked once when the sheet opens and again whenever the user
          // says so. A connection proves something is listening, not that
          // it is well — a sidecar still loading its model accepts one — so
          // this could otherwise sit reading "both are answering" directly
          // above a transcription that failed, and the two sentences would
          // disagree in the same sheet.
          trailing: TextButton(
            key: const Key('setting-sidecars-recheck'),
            onPressed: () => unawaited(_refresh()),
            child: Text(words.sidecarRecheck),
          ),
          leading: Icon(
            health.allRunning
                ? Icons.check_circle_outline
                : Icons.error_outline,
            color: health.allRunning
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
          ),
          title: Text(
            health.allRunning
                ? words.sidecarAllRunning
                : <String>[
                    for (final Sidecar stopped in health.stopped)
                      switch (stopped) {
                        Sidecar.voice => words.sidecarVoiceStopped,
                        Sidecar.ears => words.sidecarEarsStopped,
                      },
                  ].join('\n'),
          ),
          subtitle: health.allRunning ? null : Text(words.sidecarCannotStart),
        ),
      ],
    );
  }
}

/// Writing a recording the user already has out as text.
///
/// The batch recogniser is installed, tuned for this user's language, and
/// measured at 1.6% character error on zh — and until now the only way to
/// reach it was to hold a key at a live microphone. A two-hour 課堂錄音 in
/// Downloads could not use the best recogniser on the machine.
final class _TranscribeSection extends StatefulWidget {
  const _TranscribeSection({required this.run});

  /// Returns the name of the file written, empty when the user backed out,
  /// or null when nothing came back.
  final Future<String?> Function() run;

  @override
  State<_TranscribeSection> createState() => _TranscribeSectionState();
}

final class _TranscribeSectionState extends State<_TranscribeSection> {
  bool _working = false;
  String? _saved;
  bool _failed = false;

  Future<void> _start() async {
    if (_working) {
      // One at a time. The recogniser is a single-threaded sidecar, so two
      // at once is two that both take longer.
      return;
    }
    setState(() {
      _working = true;
      _saved = null;
      _failed = false;
    });
    String? name;
    bool failed = false;
    try {
      name = await widget.run();
    } on Object {
      failed = true;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _working = false;
      _failed = failed || name == null;
      // An empty name is the user backing out of one of the two panels,
      // which is not a failure and not worth reporting.
      _saved = (name != null && name.isNotEmpty) ? name : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations words = AppLocalizations.of(context);
    return SettingsSection(
      key: const Key('setting-transcribe'),
      title: words.transcribeSection,
      children: <Widget>[
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          title: Text(words.transcribeNote),
          subtitle: _working
              ? Text(words.transcribeWorking)
              : _failed
              ? Text(
                  words.transcribeFailed,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              : _saved != null
              ? Text(words.transcribeSaved(_saved!))
              : null,
          trailing: _working
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton(
                  key: const Key('setting-transcribe-choose'),
                  onPressed: () => unawaited(_start()),
                  child: Text(words.transcribeChoose),
                ),
        ),
      ],
    );
  }
}
