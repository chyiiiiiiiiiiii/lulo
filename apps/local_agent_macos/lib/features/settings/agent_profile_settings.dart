import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../agent_profile/agent_profile_store.dart';
import 'settings_section.dart';

/// Who Lulo is and how it talks, where the person talking can change it.
///
/// All of this already existed as a typed profile in a JSON file, read by the
/// prompt, the recogniser and the endpointer. The file was only ever read,
/// and the watcher that picks up a hand edit does not run in a release build
/// — so in the shipped app none of it could be changed at all.
///
/// The word lists are the sharpest case. The built-in ones are a guess about
/// how someone talks, and the only person who can disprove that guess is the
/// person talking; a rebuild is not a reasonable price for 「蛤」.
final class AgentProfileSettings extends StatelessWidget {
  /// Creates the profile settings backed by [store].
  const AgentProfileSettings({required this.store, super.key});

  /// The profile being read and written. There is no second copy: what is
  /// saved here is the file every other part of the app already reads.
  final AgentProfileStore store;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: store.revision,
      builder: (BuildContext context, int _, Widget? _) {
        final AppLocalizations words = AppLocalizations.of(context);
        final AgentProfile profile = store.current;
        // Applied to whatever the store holds when the control is used, not
        // to the profile this build captured. Two controls touched between
        // rebuilds both computed from the same stale copy, so the second
        // silently undid the first.
        void save(AgentProfile Function(AgentProfile) change) =>
            unawaited(store.save(change(store.current)));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SettingsSection(
              title: words.profileWhoItIs,
              children: <Widget>[
                _CommitField(
                  fieldKey: const Key('profile-agent-name'),
                  label: words.profileAgentName,
                  value: profile.identity.agentName,
                  onCommit: (String value) => save(
                    (AgentProfile p) => p.copyWith(
                      identity: AgentIdentity(
                        agentName: value.isEmpty ? 'Lulo' : value,
                        userName: p.identity.userName,
                        locale: p.identity.locale,
                      ),
                    ),
                  ),
                ),
                _CommitField(
                  fieldKey: const Key('profile-user-name'),
                  label: words.profileUserName,
                  hint: words.profileUserNameHint,
                  value: profile.identity.userName,
                  onCommit: (String value) => save(
                    (AgentProfile p) => p.copyWith(
                      identity: AgentIdentity(
                        agentName: p.identity.agentName,
                        userName: value,
                        locale: p.identity.locale,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: words.profileHowItTalks,
              children: <Widget>[
                _CommitField(
                  fieldKey: const Key('profile-tone'),
                  label: words.profileTone,
                  hint: words.profileToneHint,
                  value: profile.personality.tone,
                  onCommit: (String value) => save(
                    (AgentProfile p) => p.copyWith(
                      personality: _personalityWith(p, tone: value),
                    ),
                  ),
                ),
                _ResponseLengthChoice(
                  value: profile.personality.responseLength,
                  onChanged: (AgentResponseLength length) => save(
                    (AgentProfile p) => p.copyWith(
                      personality: _personalityWith(p, responseLength: length),
                    ),
                  ),
                ),
                SwitchListTile(
                  key: const Key('profile-admit-uncertainty'),
                  value: profile.personality.admitUncertainty,
                  title: Text(words.profileAdmitUncertainty),
                  subtitle: Text(words.profileAdmitUncertaintyNote),
                  onChanged: (bool value) => save(
                    (AgentProfile p) => p.copyWith(
                      personality: _personalityWith(p, admitUncertainty: value),
                    ),
                  ),
                ),
                SwitchListTile(
                  key: const Key('profile-lead-with-answer'),
                  value: profile.personality.leadWithAnswer,
                  title: Text(words.profileLeadWithAnswer),
                  onChanged: (bool value) => save(
                    (AgentProfile p) => p.copyWith(
                      personality: _personalityWith(p, leadWithAnswer: value),
                    ),
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: words.profileMemories,
              note: words.profileMemoriesNote,
              children: <Widget>[
                for (final AgentMemory memory in profile.memories)
                  _MemoryRow(
                    memory: memory,
                    onToggle: (bool enabled) => save(
                      (AgentProfile p) => p.copyWith(
                        memories: <AgentMemory>[
                          for (final AgentMemory item in p.memories)
                            if (item.id == memory.id)
                              AgentMemory(
                                id: item.id,
                                kind: item.kind,
                                content: item.content,
                                triggers: item.triggers,
                                enabled: enabled,
                                // Carried, not defaulted. Switching a
                                // memory off and on again must not turn an
                                // agent-written one into a developer one.
                                source: item.source,
                                createdAt: item.createdAt,
                              )
                            else
                              item,
                        ],
                      ),
                    ),
                    onForget: () => save(
                      (AgentProfile p) => p.copyWith(
                        memories: <AgentMemory>[
                          for (final AgentMemory item in p.memories)
                            if (item.id != memory.id) item,
                        ],
                      ),
                    ),
                  ),
                // Only when there is something to forget, and it says how
                // many. The one-button version of "I do not trust what it
                // picked up" — and the reason it deletes by source rather
                // than everything is that the user's own entries and the
                // profile file's are not what they distrust.
                if (profile.memories.any(
                  (AgentMemory m) => m.source == AgentMemorySource.agent,
                ))
                  ListTile(
                    key: const Key('profile-forget-learned'),
                    dense: true,
                    leading: Icon(
                      Icons.auto_delete_outlined,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      words.profileForgetLearnedCount(
                        profile.memories
                            .where(
                              (AgentMemory m) =>
                                  m.source == AgentMemorySource.agent,
                            )
                            .length,
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    subtitle: Text(words.profileForgetLearnedNote),
                    onTap: () => save(
                      (AgentProfile p) => p.copyWith(
                        memories: <AgentMemory>[
                          for (final AgentMemory item in p.memories)
                            if (item.source != AgentMemorySource.agent) item,
                        ],
                      ),
                    ),
                  ),
                Padding(
                  // The same inset the word lists sit at, so the two adding
                  // fields line up rather than one running the full width.
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: _AddField(
                    fieldKey: const Key('profile-add-memory'),
                    hint: words.profileAddMemoryHint,
                    // Through the same write path the agent's own memories
                    // go through, so one place owns the length bound, the
                    // ceiling, the duplicate check, and the rule that a
                    // triggerless memory has to be a kind that can be
                    // recalled. A rejected write leaves the list alone,
                    // which is what the field's own emptiness then says.
                    onAdd: (String content) => save(
                      (AgentProfile p) => p.copyWith(
                        memories: writeAgentMemory(
                          profile: p,
                          content: content,
                          // Typed here, on purpose, so it is not screened:
                          // an instruction the user writes themselves is one
                          // they meant.
                          source: AgentMemorySource.user,
                          now: DateTime.now(),
                        ).memories,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: words.profileWords,
              note: words.profileWordsNote,
              children: <Widget>[
                // The one that always works comes first. Vocabulary is a
                // hint the recogniser may ignore — and on the corpus in
                // `SpokenVocabularyBook`, ignored entirely — while a
                // correction is a substitution. A user who has just been
                // misheard should reach the working one first.
                _MisheardList(
                  words: profile.misheard,
                  onChanged: (List<MisheardWord> words) =>
                      save((AgentProfile p) => p.copyWith(misheard: words)),
                ),
                _WordList(
                  name: 'vocabulary',
                  title: words.profileVocabulary,
                  note: words.profileVocabularyNote,
                  hint: words.profileVocabularyHint,
                  words: profile.vocabulary,
                  onChanged: (List<String> words) =>
                      save((AgentProfile p) => p.copyWith(vocabulary: words)),
                ),
              ],
            ),
            SettingsSection(
              title: words.profileTurnTaking,
              note: words.profileTurnTakingNote,
              children: <Widget>[
                _WordList(
                  name: 'acknowledgements',
                  title: words.profileCarryOn,
                  note: words.profileCarryOnNote,
                  hint: words.profileCarryOnHint,
                  words: profile.turnTaking.acknowledgements,
                  onChanged: (List<String> words) => save(
                    (AgentProfile p) => p.copyWith(
                      turnTaking: _turnTakingWith(p, acknowledgements: words),
                    ),
                  ),
                ),
                _WordList(
                  name: 'corrections',
                  title: words.profileStop,
                  note: words.profileStopNote,
                  hint: words.profileStopHint,
                  words: profile.turnTaking.corrections,
                  onChanged: (List<String> words) => save(
                    (AgentProfile p) => p.copyWith(
                      turnTaking: _turnTakingWith(p, corrections: words),
                    ),
                  ),
                ),
                _WordList(
                  name: 'unfinished',
                  title: words.profileUnfinished,
                  note: words.profileUnfinishedNote,
                  hint: words.profileUnfinishedHint,
                  words: profile.turnTaking.unfinished,
                  onChanged: (List<String> words) => save(
                    (AgentProfile p) => p.copyWith(
                      turnTaking: _turnTakingWith(p, unfinished: words),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

AgentPersonality _personalityWith(
  AgentProfile profile, {
  String? tone,
  AgentResponseLength? responseLength,
  bool? admitUncertainty,
  bool? leadWithAnswer,
}) {
  return AgentPersonality(
    tone: tone ?? profile.personality.tone,
    responseLength: responseLength ?? profile.personality.responseLength,
    admitUncertainty: admitUncertainty ?? profile.personality.admitUncertainty,
    leadWithAnswer: leadWithAnswer ?? profile.personality.leadWithAnswer,
  );
}

TurnTakingWords _turnTakingWith(
  AgentProfile profile, {
  List<String>? acknowledgements,
  List<String>? corrections,
  List<String>? unfinished,
}) {
  return TurnTakingWords(
    acknowledgements: acknowledgements ?? profile.turnTaking.acknowledgements,
    corrections: corrections ?? profile.turnTaking.corrections,
    unfinished: unfinished ?? profile.turnTaking.unfinished,
  );
}

/// One of the three word lists, with a way in and a way out.
final class _WordList extends StatelessWidget {
  const _WordList({
    required this.name,
    required this.title,
    required this.note,
    required this.hint,
    required this.words,
    required this.onChanged,
  });

  final String name;
  final String title;
  final String note;
  final String hint;
  final List<String> words;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 2),
          Text(
            note,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (words.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final (int index, String word) in words.indexed)
                  InputChip(
                    label: Text(word),
                    // Keyed on the delete icon rather than the chip: the chip
                    // body is not what removes the word, and a word that
                    // vanished because the user brushed past it would be
                    // worse than one they cannot remove at all.
                    //
                    // Keyed by position rather than by the word itself. The
                    // decoder does not de-duplicate, so a hand-edited
                    // profile can list one word twice — and removing by
                    // value took both away at once, while two chips shared
                    // one key.
                    deleteIcon: Icon(
                      Icons.close_rounded,
                      key: Key('profile-remove-$name-$word'),
                      size: 16,
                    ),
                    onDeleted: () => onChanged(<String>[
                      ...words.take(index),
                      ...words.skip(index + 1),
                    ]),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          _AddField(
            fieldKey: Key('profile-add-$name'),
            hint: hint,
            onAdd: (String word) {
              if (words.contains(word)) {
                return;
              }
              onChanged(<String>[...words, word]);
            },
          ),
        ],
      ),
    );
  }
}

/// One remembered fact: whether it counts, and a way to forget it.
/// Who wrote a memory and when, as one short line under it.
///
/// The date is plain `YYYY-MM-DD` rather than 「三天前」: a memory list is
/// read when something in it looks wrong, and at that moment an exact date
/// is what lets it be lined up against a conversation. Absent for entries
/// written before provenance existed, which say only where they came from.
String _provenance(BuildContext context, AgentMemory memory) {
  final AppLocalizations words = AppLocalizations.of(context);
  final String who = switch (memory.source) {
    AgentMemorySource.agent => words.profileMemoryByAgent,
    AgentMemorySource.user => words.profileMemoryByUser,
    AgentMemorySource.developer => words.profileMemoryByDeveloper,
  };
  final DateTime? when = memory.createdAt;
  if (when == null) {
    return who;
  }
  final String month = when.month.toString().padLeft(2, '0');
  final String day = when.day.toString().padLeft(2, '0');
  return '$who · ${when.year}-$month-$day';
}

final class _MemoryRow extends StatelessWidget {
  const _MemoryRow({
    required this.memory,
    required this.onToggle,
    required this.onForget,
  });

  final AgentMemory memory;
  final ValueChanged<bool> onToggle;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Switch(
        key: Key('profile-memory-enabled-${memory.id}'),
        value: memory.enabled,
        onChanged: onToggle,
      ),
      title: Text(
        memory.content,
        style: memory.enabled
            ? null
            : TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      // Who wrote it, and when. Not decoration: a memory the agent extracted
      // by itself can be an ordinary fact or a directive laundered into the
      // shape of one, and `memory-is-an-attack-surface.md` measures that the
      // second kind is not distinguishable by pattern. The person reading
      // this row is the classifier that still works, and they cannot be one
      // without being told which rows nobody checked.
      subtitle: Text(_provenance(context, memory)),
      trailing: IconButton(
        key: Key('profile-forget-${memory.id}'),
        tooltip: AppLocalizations.of(context).profileForget,
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: onForget,
      ),
    );
  }
}

/// How much Lulo says when the question does not demand more.
final class _ResponseLengthChoice extends StatelessWidget {
  const _ResponseLengthChoice({required this.value, required this.onChanged});

  final AgentResponseLength value;
  final ValueChanged<AgentResponseLength> onChanged;

  static Map<AgentResponseLength, String> _labels(AppLocalizations words) =>
      <AgentResponseLength, String>{
        AgentResponseLength.concise: words.lengthShort,
        AgentResponseLength.balanced: words.lengthEnough,
        AgentResponseLength.detailed: words.lengthThorough,
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations words = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            words.profileHowMuch,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: <Widget>[
              for (final MapEntry<AgentResponseLength, String> entry in _labels(
                words,
              ).entries)
                ChoiceChip(
                  key: Key('profile-length-${entry.key.name}'),
                  label: Text(entry.value),
                  selected: entry.key == value,
                  onSelected: (bool _) => onChanged(entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A field that adds what was typed and then clears itself.
final class _AddField extends StatefulWidget {
  const _AddField({
    required this.fieldKey,
    required this.hint,
    required this.onAdd,
  });

  final Key fieldKey;
  final String hint;
  final ValueChanged<String> onAdd;

  @override
  State<_AddField> createState() => _AddFieldState();
}

final class _AddFieldState extends State<_AddField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final String value = _controller.text.trim();
    if (value.isEmpty) {
      return;
    }
    _controller.clear();
    widget.onAdd(value);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return TextField(
      key: widget.fieldKey,
      controller: _controller,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest,
        hintText: widget.hint,
        // Sized and coloured down from the body text around it. At the
        // default the hint reads as a heading and the field — which has no
        // border of its own — does not read as somewhere to type at all.
        hintStyle: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide.none,
        ),
        suffixIcon: IconButton(
          tooltip: AppLocalizations.of(context).addTooltip,
          icon: const Icon(Icons.add_rounded, size: 18),
          onPressed: _add,
        ),
        suffixIconConstraints: const BoxConstraints.tightFor(
          width: 40,
          height: 36,
        ),
      ),
      onSubmitted: (String _) => _add(),
    );
  }
}

/// A field whose value is applied when the user is finished with it.
///
/// On submit and on losing focus, not on every keystroke: each save rewrites
/// the profile file, and a name typed one character at a time would rewrite
/// it once per character.
final class _CommitField extends StatefulWidget {
  const _CommitField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onCommit,
    this.hint,
  });

  final Key fieldKey;
  final String label;
  final String? hint;
  final String value;
  final ValueChanged<String> onCommit;

  @override
  State<_CommitField> createState() => _CommitFieldState();
}

final class _CommitFieldState extends State<_CommitField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_commitOnLeaving);
  }

  @override
  void didUpdateWidget(_CommitField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only while the user is not in the middle of typing into it: the profile
    // can change under this field when a hand edit to the file is picked up.
    if (!_focus.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_commitOnLeaving);
    // Typing and then closing the sheet used to throw the edit away: Esc and
    // the close button both tear this down without ever moving focus off the
    // field, so the only two paths that commit — submit and losing focus —
    // neither fired. Nothing was said, and the sheet reopened showing the
    // old value.
    _commit();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commitOnLeaving() {
    if (!_focus.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    final String value = _controller.text.trim();
    if (value == widget.value) {
      return;
    }
    widget.onCommit(value);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        key: widget.fieldKey,
        controller: _controller,
        focusNode: _focus,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest,
          labelText: widget.label,
          labelStyle: theme.textTheme.bodySmall,
          hintText: widget.hint,
          hintStyle: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          contentPadding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide.none,
          ),
        ),
        onSubmitted: (String _) => _commit(),
      ),
    );
  }
}

/// The corrections the user has taught, and a way to teach another.
///
/// Two fields rather than one, because a correction is a pair: what the
/// recogniser produced and what was actually said. `_WordList` next door
/// takes single words and cannot express that.
final class _MisheardList extends StatefulWidget {
  const _MisheardList({required this.words, required this.onChanged});

  final List<MisheardWord> words;
  final ValueChanged<List<MisheardWord>> onChanged;

  @override
  State<_MisheardList> createState() => _MisheardListState();
}

final class _MisheardListState extends State<_MisheardList> {
  final TextEditingController _heard = TextEditingController();
  final TextEditingController _meant = TextEditingController();

  @override
  void dispose() {
    _heard.dispose();
    _meant.dispose();
    super.dispose();
  }

  void _add() {
    final MisheardWord word = MisheardWord(
      heard: _heard.text.trim(),
      meant: _meant.text.trim(),
    );
    // A half-filled pair is not a correction, and a blank left-hand side
    // would match between every pair of characters in every transcript.
    if (!word.isUsable || word.meant.isEmpty) {
      return;
    }
    // Replacing case-insensitively, because matching is case-insensitive:
    // comparing exactly here let the editor create two rules that both
    // claim the same span, whose winner then depended on which was typed
    // first.
    // Trimmed on both sides, because that is what matching compares. The
    // stored value was compared raw while the typed one was trimmed, so a
    // rule saved with a stray space survived being replaced — and then won,
    // leaving the user with a chip that said one thing and a transcript
    // that kept doing the other.
    final String key = word.heard.toLowerCase();
    widget.onChanged(<MisheardWord>[
      ...widget.words.where(
        (MisheardWord other) => other.heard.trim().toLowerCase() != key,
      ),
      word,
    ]);
    _heard.clear();
    _meant.clear();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations words = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          title: Text(words.profileMisheard),
          subtitle: Text(words.profileMisheardNote),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final (int index, MisheardWord word) in widget.words.indexed)
                InputChip(
                  label: Text('${word.heard} → ${word.meant}'),
                  // The key belongs on the delete icon, not the chip: tapping
                  // the chip's body does not remove it, so a key there is a
                  // handle onto something that looks tappable and is not.
                  // Keyed by position, not by content. A hand-edited file can
                  // hold the same rule twice, and a key made from `heard`
                  // would then name two chips — and removing by value equality
                  // took both of them away at once.
                  deleteIcon: Icon(
                    Icons.close,
                    key: Key('profile-forget-misheard-$index'),
                    size: 18,
                  ),
                  onDeleted: () => widget.onChanged(<MisheardWord>[
                    ...widget.words.take(index),
                    ...widget.words.skip(index + 1),
                  ]),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('profile-misheard-heard'),
                  controller: _heard,
                  decoration: InputDecoration(
                    labelText: words.profileMisheardHeardHint,
                  ),
                  onSubmitted: (String _) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('profile-misheard-meant'),
                  controller: _meant,
                  decoration: InputDecoration(
                    labelText: words.profileMisheardMeantHint,
                  ),
                  onSubmitted: (String _) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('profile-misheard-add'),
                onPressed: _add,
                child: Text(words.profileMisheardAdd),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
