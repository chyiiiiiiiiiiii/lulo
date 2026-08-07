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
phrases, identity numbers, medical records or financial secrets in it. Storage
encryption, sensitive-category policy and public memory controls require their
own privacy slice before automatic memory writing is enabled.
