# Agent profile

Lulo's personality is a typed local profile, not one editable system-prompt
blob. Stable behavior, personal facts and the current question stay separate
so the model receives only the context it needs for this turn.

## Developer file

During development edit:

```text
~/Library/Application Support/Lulo/agent_profile.json
```

Debug and profile builds watch this file. A valid save applies to the next
generation without restarting Lulo or changing an answer already in flight.
An invalid save leaves the last valid profile active. Deleting the file
restores the built-in profile.

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
  "turnTaking": {
    "acknowledgements": ["蛤", "真的假的喔"],
    "corrections": ["先停"],
    "unfinished": ["我的意思是說"]
  },
  "vocabulary": ["Lulo", "Flutter", "MLX", "Codex"],
  "additionalInstructions": ["不要空泛稱讚；有不同判斷時直接說明。"]
}
```

`responseLength` accepts `concise`, `balanced` or `detailed`. A memory
`kind` is `personal`, `preference`, `project` or `vocabulary`.

`vocabulary` is the one list with two consumers and they work at different
moments. The transcript refiner reads it in Dart and refuses to edit those
words away — a repair after the fact. The recogniser is biased towards them
before any audio is decoded, which is Apple's `contextualStrings`; that is
native, so the profile is pushed across through
`VoiceHostApi.useSpokenVocabulary` when the ears open and again whenever the
list changes. It was pushed nowhere at all until recently: this file claimed
the recogniser leaned on the profile while the recogniser in fact ran off a
hardcoded list of its own, and the only vocabulary it ever learned came from
the agent's own spoken answers.

`misheard` is the other half of the same problem and the half that works.
`vocabulary` asks the recogniser to lean towards a word and it may do
nothing with the request; `misheard` holds `heard → meant` pairs and
`DeterministicTranscriptRefiner` substitutes them, so a word the user has
corrected once is corrected every time after. It runs **after** the
vocabulary casing pass — whatever runs last wins, and with the order the
other way a term typed into `vocabulary` in the wrong case silently undid a
correction. Word breaks are checked per end rather than for the rule as a
whole, or 「台中 weather」 and every other mixed-script rule would fire inside
longer words. A row missing either half is dropped when the file is read: an
empty `heard` matches between every pair of characters, so one bad row in a
hand-edited profile would rewrite everything the user says.

Do not read the wiring as an accuracy win. `SpokenVocabularyBook` carries a
measurement where a thirty-two term bias changed the transcript by not one
character, and nothing since has shown otherwise. What was broken and is now
fixed is that the setting reaches the thing it names.
Unknown fields are ignored. Invalid memories are skipped independently.

## The tone field is empty until it is yours

`AgentPersonality.tone` defaults to 「親近但不裝熟」, and `composeAgentPrompt`
deliberately **does not send it** while it still equals that default: the core
identity block already states the built-in tone, in the language of the
question, and repeating it said the same thing twice — in Chinese, inside an
English instruction, in a composer whose own comment says a small model
answers in the language it was instructed in.

So the editor leaves the field **empty** while it is inherited, with the hint
naming what the built-in tone is. A pre-filled field showed an instruction
that was not in force, which is misleading in either language and became
plainly wrong once the agent started opening in English. Typing in it makes
the tone yours and sends it as written, in whatever language you wrote it;
clearing it goes back to inherited. Both states are pinned by tests in
`agent_profile_settings_test.dart`.

## The words you take and yield the floor with

`turnTaking` is the one section that changes how the agent *listens* rather
than how it answers. Every list extends a built-in one rather than replacing
it, and every built-in one is a guess at how people talk — which is exactly
the kind of guess a user's own habits disprove.

| Key | Said when | What it does | Where it is read |
|---|---|---|---|
| `acknowledgements` | while the agent is speaking | never interrupts, at any length | `FloorControl`, Dart |
| `corrections` | while the agent is speaking | always interrupts, however short | `FloorControl`, Dart |
| `unfinished` | at the end of your own sentence | the endpointer waits 1.4s instead of 0.8s | `TurnCompletion`, Swift |

How each is matched, which is worth knowing before adding a short one:

- An `acknowledgements` entry of **one character** joins the repeatable set,
  so 「蛤」 also covers 「蛤蛤蛤」 the way 嗯 covers 嗯嗯. Anything longer is
  matched **whole**, because a phrase with words after it is a question.
- A `corrections` entry containing Han is a **prefix**, so 「先停」 also stops
  the agent on 「先停一下我想想」. An entry in Latin contributes its **first
  word**, so `"hang on"` matches "hang" and not "hanging".
- An `unfinished` entry is a **suffix** of the partial transcript.
- A word listed in both `acknowledgements` and `corrections` is a
  correction. Being unable to stop the agent is the worse failure.

The first two take effect on the next thing said, because the file is
watched and the policy is read at every ruling. `unfinished` is pushed
across to the native endpointer once per settled utterance, so it takes
effect on the next turn — a beat later, and not something anyone edits
mid-sentence.

Watch them working with Settings › Taking turns › *Show why it took the
floor*. See
[../decisions/turn-taking-by-words.md](../decisions/turn-taking-by-words.md)
for why these are lexicons rather than a model.

## Selection and bounds

Personal and preference memories without triggers are eligible on every turn.
Other memories require a case-insensitive substring trigger in the current
question. Longer matching triggers rank first; ties preserve file order.

The selector injects at most six memories and 600 memory characters. The whole
profile-derived context is capped at 1,200 characters. It never cuts a memory
in half, never copies the conversation archive into the profile, and never
logs profile or memory content. Diagnostics may use stable memory IDs.

## Writing: one path, and it supersedes

Three things write memories, and all of them go through
`writeAgentMemory` in `agent_core` so that one place owns the bounds:
the settings sheet's add field, `RememberTool`, and the extraction pass.

Every entry records **who wrote it** — `AgentMemorySource` is `developer`
(hand-authored in the file), `user` (typed into Settings) or `agent`
(extracted by the second pass) — plus `createdAt` where it is known. That
is provenance, and it is the first control OWASP's memory-poisoning
guidance asks for. It also decides screening: content written by the
`agent` path is checked for instruction shapes and secrets before it is
persisted, and content the user typed is not, because an instruction they
wrote on purpose is one they meant. See
[../decisions/memory-is-an-attack-surface.md](../decisions/memory-is-an-attack-surface.md).

It takes a `replaces` list, and that is the point of it. **Append-only
memory is worse than no memory:** a profile that learns 「使用者住在台北」 in
March and 「使用者搬到台南了」 in August keeps both, both are triggerless
personal memories, both are eligible for the same turn, and the model is
handed two contradictory facts at two shares of the 1,200-character budget.

What it enforces:

- 160 characters per memory, 60 memories total — both sized against the
  prompt budget above, not against language.
- The same sentence twice is `unchanged`, not a second row. Compared
  case-folded, space-stripped, and without a trailing full stop, because a
  model rewrites its own wording between turns.
- A **replacement is never blocked by the ceiling**. A cap that stops
  corrections makes the list unfixable exactly when it is most full of
  things worth fixing.
- A superseded id is never reused for the memory that superseded it.
- A triggerless `project` or `vocabulary` is stored as `personal`, because
  the selector above would never surface it otherwise — a write that
  reports success and cannot be read back is the worst of the outcomes.

What it deliberately does **not** do is guess what supersedes what. That is
semantics, and a string-similarity threshold cannot separate a rewrite from
a contradiction across two languages; the numbers are in
[../decisions/the-model-will-not-interrupt-itself-to-remember.md](../decisions/the-model-will-not-interrupt-itself-to-remember.md).
The caller says.

## Where written memories come from

Not a tool. `RememberTool` exists, is bounded and tested, and is **not
registered** — gemma-4-E4B does not call it, 0/5 across eleven conditions,
including one where the user says 「記住我住在台南」 outright. Asked to
remember, it answers 「我記住了」 and writes nothing.

What works instead is a second pass, measured at 15/15 recall and 0/15 false
keeps: after a turn finishes, `AgentMemoryExtractor` sends what the user
said to the same model with no persona and no tools, and reads back one
sentence or `NONE`. When the profile already holds memories they are listed
in that prompt, so one pass both keeps a fact and names what it retires.

**It is off by default.** See the privacy boundary below.

## Prompt order

Each local-model request is composed immediately before native generation,
and arrives in **two halves** because they cost different amounts to say
twice:

```text
systemInstruction — prefilled once per conversation
  core identity
  spoken-response behavior, including the sentence budget
  user preferences
  additional developer instructions

turnInstruction — read again with every question
  relevant structured memories
  current question
```

The bounded recent conversation remains on the native history field. The
question appears exactly once.

The split is the whole point. Sent as one block inside every user message,
the stable half was re-prefilled on every turn: measured on `gemma-4-E4B-it`
at **1.7s to the first token against 0.3s** when it sits in the
conversation's own system message. Memories stay with the question because
they are chosen against it — `selectAgentMemories` reads the prompt — so
they are not stable and cannot be cached. Developer instructions moved ahead
of memories for the same reason: the stable half has to end at the same
place every turn. See
[../decisions/voice-turn-latency.md](../decisions/voice-turn-latency.md).

The 1,200-character cap still bounds both halves together, so a profile full
of memories cannot grow the prompt by moving text across the seam.

## The spoken length is a number, not an adjective

`responseLength` renders as a sentence budget inside the spoken-response
section rather than as a word in the preferences. Spelled out only as 簡潔 /
`concise`, gemma-4-E4B answered five conversational questions in 172
characters on average — twenty-seven seconds of Mandarin speech, for a
question nobody would spend twenty-seven seconds answering out loud. The same
profile with `回答控制在三句話以內` answered in 91, and shortened every one of the
five. Three of the five ended by asking a question back, which the long
answers never did.

| `responseLength` | Budget |
|---|---|
| `concise` | three sentences |
| `balanced` | five sentences |
| `detailed` | no count — "still talking, not writing" |

The budget carries a second clause — 講完核心就停，細節等使用者追問再說 — because
telling a model to stop is not the same as telling it where the rest of the
answer went. With it, stopping reads as leaving room rather than running out.

It is gated on `voiceBehavior.preferNaturalShortSentences`: a profile that
has turned spoken-sentence shaping off does not get a budget either.

A profile the user edits changes the system message, and a prefilled KV
cache cannot be amended in place. The runtime driver notices and rebuilds
the conversation from stored history.

## Privacy boundary

The profile is local but currently plaintext. Do not put passwords, recovery
phrases, identity numbers, medical records or financial secrets in it.

Automatic memory writing exists and **starts off**. The `rememberFacts`
setting, beside `shareFrontmostApp` in Settings, is what turns it on;
`AppSettings` reads a missing key as false, so a settings file written
before the feature is never read as consent. Nothing is written about the
user until they ask for it, and everything that is written is a row on this
sheet with a switch and a forget button.

This document used to make storage encryption, a sensitive-category policy
and public memory controls the precondition for automatic writing. Two of
those are now built and the third is retired:

- **A way to see what was kept without opening a JSON file** — every row
  says who wrote it and when, and one action forgets everything the agent
  wrote while leaving what you typed alone.
- **A sensitive-category policy** — `screenAgentMemory` refuses credentials
  and identifiers on the `agent` path. Deliberately about credentials
  rather than topics: a rule broad enough to catch 「我最近在看醫生」 would
  refuse a large share of what a person says about themselves.
- **Encryption at rest** — retired rather than deferred. Every directory
  above the profile is `0700` and FileVault covers the disk, so the threats
  it stood for are the OS's and already handled; the reasoning is in
  [../decisions/memory-is-an-attack-surface.md](../decisions/memory-is-an-attack-surface.md).

The default stays off regardless. Those were preconditions for it being
*reasonable*, not a switch that flips itself — whether an assistant should
write down what it hears is the user's call, not a checklist's.
