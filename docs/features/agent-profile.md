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

Each local-model request is composed immediately before native generation:

```text
core identity
spoken-response behavior
user preferences
relevant structured memories
additional developer instructions
current question
```

The bounded recent conversation remains on the native history field. The
question appears exactly once.

## Privacy boundary

The profile is local but currently plaintext. Do not put passwords, recovery
phrases, identity numbers, medical records or financial secrets in it. Storage
encryption, sensitive-category policy and public memory controls require their
own privacy slice before automatic memory writing is enabled.
