# Developer Agent Profile Design

Date: 2026-08-01
Status: approved for planning

## Goal

Give Lulo a complete, stable personality and a small set of structured personal
memories that the developer can configure immediately, without building the
public onboarding and settings experience yet.

The first release must make the configured behavior visible in the next model
turn, keep prompt growth bounded, and never use the full conversation archive
as a substitute for personal memory.

## Scope

This slice includes:

- a typed local agent profile;
- a durable JSON profile store;
- deterministic prompt composition;
- bounded selection of relevant structured memories;
- developer-mode live reload;
- diagnostics that describe which profile sections were used without logging
  their private contents;
- documentation of the future public configuration experience.

It does not include automatic memory extraction, a public profile editor,
onboarding, semantic embeddings, cloud synchronization, or changes to the TTS,
ASR, transcript-refinement, and turn-detection pipelines.

## Product Contract

Lulo has a stable built-in identity even when no profile file exists:

- answer in Taiwanese Traditional Chinese when the user speaks Chinese;
- be warm without pretending to be more familiar than the relationship
  supports;
- lead with the useful answer;
- be concise by default;
- state uncertainty honestly instead of filling gaps;
- use natural spoken sentences;
- avoid reading Markdown syntax and full URLs aloud;
- avoid long lists in voice responses;
- offer to expand when a complex answer cannot remain short.

The developer profile customizes this identity. It does not replace the
built-in behavioral and safety contract.

## Configuration File

The durable file is:

```text
~/Library/Application Support/Lulo/agent_profile.json
```

The initial schema is versioned:

```json
{
  "schemaVersion": 1,
  "identity": {
    "agentName": "Lulo",
    "userName": "Yii",
    "locale": "zh-TW"
  },
  "personality": {
    "tone": "親近但不裝熟",
    "responseLength": "concise",
    "admitUncertainty": true,
    "leadWithAnswer": true
  },
  "voiceBehavior": {
    "avoidMarkdown": true,
    "avoidReadingUrls": true,
    "avoidLongLists": true,
    "preferNaturalShortSentences": true
  },
  "memories": [
    {
      "id": "project-lulo",
      "kind": "project",
      "content": "Yii 正在開發地端 macOS Agent Lulo。",
      "triggers": ["Lulo", "地端 Agent", "flutter_local_agent"],
      "enabled": true
    }
  ],
  "vocabulary": ["Lulo", "Flutter", "MLX"],
  "additionalInstructions": []
}
```

Unknown fields are ignored so a newer file can be opened by an older build.
Unknown enum values fall back to their built-in defaults. Invalid memory
entries are skipped independently rather than invalidating the entire profile.
An unreadable file or unsupported schema version uses the built-in profile and
reports one visible, non-fatal configuration error.

Writes performed by future Lulo UI use an atomic temporary-file rename. This
slice reads the file but does not rewrite a developer-authored file.

## Domain Model

The profile is a typed immutable value composed of:

- `AgentIdentity` for agent name, user name, and locale;
- `AgentPersonality` for tone, response length, uncertainty, and answer order;
- `VoiceResponseBehavior` for spoken-output constraints;
- `AgentMemory` for one structured fact;
- `AgentProfile` as the versioned aggregate.

`AgentMemory.kind` is one of `personal`, `preference`, `project`, or
`vocabulary`. Every memory has a stable ID, content, explicit triggers, and an
enabled flag. Raw conversation turns are not an `AgentMemory` and cannot enter
this store through this slice.

The domain model and selector remain pure Dart in `packages/agent_core`.
Filesystem watching and JSON persistence remain in the macOS app.

## Memory Selection

Memory selection is deterministic and deliberately simple in v1.

1. Disabled entries are removed.
2. `personal` and `preference` entries with no triggers are always eligible.
3. Other entries are eligible when the normalized current user message
   contains at least one normalized trigger.
4. Exact trigger matches outrank triggerless entries; longer matching triggers
   outrank shorter ones; ties preserve file order.
5. At most six entries and 600 Unicode characters are selected.
6. Content is deduplicated before prompt composition.

This avoids an embedding dependency and makes every injected memory
explainable. Chinese memories do not depend on whitespace tokenization because
matching uses normalized substring triggers chosen by the developer.

## Prompt Composition

Prompt assembly becomes one dedicated pure component. It receives the
built-in contract, the current `AgentProfile`, selected memories, and the
current user message. It returns a single instruction block plus metadata about
the IDs of memories it selected.

The block order is fixed:

```text
[核心人格]
[語音回答方式]
[使用者偏好]
[與這次問題相關的記憶]
[開發者額外指示]
[問題]
```

Empty sections are omitted. The current question appears exactly once. The
existing bounded recent-turn history remains in the native conversation
history field and is not copied into the instruction block.

The profile contributes only concise structured statements. The composer caps
the complete profile-derived portion at 1,200 Unicode characters. Built-in
behavioral rules are always retained if custom content reaches the cap.

## Loading and Live Reload

`AgentProfileStore` exposes the current profile and a listenable revision.
Production startup loads once. In debug/profile development builds, a file
watcher observes `agent_profile.json` and debounces changes for 250 ms.

A valid change replaces the in-memory profile and affects the next generation;
it never mutates an in-flight generation. An invalid change leaves the last
valid in-memory profile active and exposes the parse error. File deletion
restores the built-in profile. The watcher is disposed with `AppComposition`.

No profile value or memory content is written to diagnostic logs. Diagnostics
may report schema version, profile revision, selected memory IDs, selected
count, and composed character count.

## Error Handling

- Missing file: use the built-in profile without an error.
- Invalid JSON: retain the last valid in-memory profile and show a non-fatal
  error.
- Unsupported schema: retain the last valid profile and show a non-fatal
  error.
- Invalid individual memory: skip it and report its ID when available.
- Watcher failure: keep the loaded profile and stop live reload; generation
  remains available.
- Prompt limit exceeded: truncate custom memories and additional instructions,
  never the built-in contract or current question.

## Composition Boundaries

`app/bootstrap.dart` constructs the durable profile store. `AppComposition`
owns and disposes it. The conversation feature receives an `AgentContextProvider`
interface rather than reading files or global state. The inference adapter asks
that provider to compose context immediately before starting a generation.

This keeps filesystem concerns out of the ViewModel and keeps
`packages/agent_core` free of Flutter and platform imports.

## Testing

Red/Green tests cover:

- JSON defaults, valid decoding, unknown fields, invalid memories, and
  unsupported schemas;
- deterministic memory selection, Chinese substring triggers, ordering,
  deduplication, and both bounds;
- prompt section order, language behavior, question uniqueness, built-in rule
  preservation, and bounded custom content;
- missing, valid, malformed, changed, and deleted profile files;
- live reload affecting the next request but not an in-flight request;
- composition-root ownership and disposal;
- generation requests containing the composed profile and only the existing
  bounded conversation history.

The project gate remains `dart run tool/verify.dart`.

## Future Public Configuration Experience

The public product will reuse the same schema behind:

- a short conversational onboarding;
- human-readable personality, language, voice, and answer-length controls;
- memory proposal cards requiring confirmation by default;
- source, scope, edit, disable, and delete controls for each memory;
- sensitive-data categories that are never saved automatically;
- pause, export, and erase-all-memory controls;
- an advanced `Additional instructions` field instead of exposing the raw
  system prompt.

Automatic memory extraction and semantic retrieval require their own design
and privacy review before they can write to this profile.

## Follow-on Slices

After this profile slice is implemented and measured, separate specifications
will cover:

1. the Taiwanese Mandarin golden audio and evaluation harness;
2. Qwen reference-corpus and prosody continuity experiments;
3. the reversible Typeless-style transcript refiner;
4. Pipecat Smart Turn v3 shadow evaluation.
