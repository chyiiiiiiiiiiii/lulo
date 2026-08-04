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
  "vocabulary": ["Lulo", "Flutter", "MLX", "Codex"],
  "additionalInstructions": ["不要空泛稱讚；有不同判斷時直接說明。"]
}
```

`responseLength` accepts `concise`, `balanced` or `detailed`. A memory
`kind` is `personal`, `preference`, `project` or `vocabulary`.
Unknown fields are ignored. Invalid memories are skipped independently.

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
  spoken-response behavior
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

A profile the user edits changes the system message, and a prefilled KV
cache cannot be amended in place. The runtime driver notices and rebuilds
the conversation from stored history.

## Privacy boundary

The profile is local but currently plaintext. Do not put passwords, recovery
phrases, identity numbers, medical records or financial secrets in it. Storage
encryption, sensitive-category policy and public memory controls require their
own privacy slice before automatic memory writing is enabled.
