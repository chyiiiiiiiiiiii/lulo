# Which voice says Taiwan Mandarin properly

Status: measured, not yet adopted. 2026-08-04.

## The complaint, made falsifiable

"He sometimes gets the tone a bit wrong on some nouns and some characters."

True, and impossible to act on. So: render `這個詞是X。` with a candidate
voice, send it back through Whisper, and see whether X returns. The carrier
is what makes this work — a sentence with meaning would let the recogniser
repair a mispronunciation from context, and "this word is X" gives it
grammar and no clue at all.

The resident voice, on its own reference recording:

```
這個詞是企業。 -> 这个词是奇幼
這個詞是危險。 -> 这个词是吸混
這個詞是攜帶。 -> 这个词是头戴
這個詞是品質。 -> 这个词是品机
這個詞是蝸牛。 -> 这个词是犀牛
這個詞是音樂。 -> 这个词是音卧
這個詞是成長。 -> 这个词是成整
這個詞是編譯。 -> 这个词是偏西
這個詞是結構。 -> 这个词是极口
這個詞是檸檬。 -> 这个词是鸡蒙
```

Four carrier characters perfect every time, the word under test destroyed.
This is not a subtle accent. Ten of thirty-seven probe words come out as a
different word, and 企業, 結構, 編譯 and 模型 are words this agent says
about its own work constantly.

## What was measured

Thirty-seven probes: four tone controls, nine words where Taiwan and the
mainland disagree about the reading, ten polyphones in matched pairs, six
一/不 sandhi cases, eight technical nouns. Every render written to a file;
nothing was played.

| Candidate | Words survived | RTF, probes | RTF, real sentence |
|---|---|---|---|
| Qwen3-TTS 0.6B Base 8bit (resident) | 27/37 — 73% | 0.60 | 0.60 |
| IndexTTS-1.5 (same reference audio) | 13/37 — 35% | 1.30 | — |
| **VoxCPM2 4bit, 10 steps** | **36/37 — 97%** | 2.47 | 1.78 |
| **VoxCPM2 4bit, 4 steps** | **33/37 — 89%** | 1.09 | **0.85** |

VoxCPM2 at its default step count says every one of the ten words the
resident voice destroys. Its single miss is 部署 transcribed as 部属,
which is the same sound — on pronunciation it is effectively perfect.

RTF below 1 is the bar: above it, generation cannot keep up with playback.
The probe figures are pessimistic because a six-character utterance is
mostly fixed overhead; the real-sentence column is the one that decides,
measured on a 10-second answer of the kind the agent actually gives.

## The trade

VoxCPM2's `inference_timesteps` buys accuracy with time, and the two
useful settings sit on either side of the real-time line:

- **10 steps**: 97% correct, RTF 1.78 — cannot keep up with speech.
- **4 steps**: 89% correct, RTF 0.85 — keeps up, and still well clear of
  the resident voice's 73%.

At 4 steps two of the four controls fail (媽媽 came back as 爸爸), which is
a warning worth taking seriously rather than a rounding error.

## IndexTTS, and why it is out

IndexTTS-1.5 is the only candidate that accepts **pinyin annotation**:
write `qi4業` and the reading is dictated rather than guessed, which would
be a deterministic fix for exactly this defect. mlx-audio carries the
backend and the tone-digit pattern is in its text normaliser.

It scored 35%. Every utterance began with garbage — `這個詞是` came back as
`非非` or `飛飛` — which looks like a fault in how this repository drives
it rather than in the model, and it was not worth chasing: at RTF 1.30 it
cannot keep up with speech even when it is right.

Worth revisiting only if the pinyin route becomes the strategy.

The resident Qwen3-TTS does **not** accept pinyin. `qi1業` renders as
七一一 — it reads the digits.

## Recommendation

Move to VoxCPM2 at 4 steps, keeping ryan's reference recording so the voice
stays the same person. It is a 16-point improvement in whether the agent
says the word it meant, at a real-time factor that still keeps ahead of
playback.

Two things to settle before it ships, neither of which should be decided at
three in the morning:

1. **The controls at 4 steps.** 媽媽 → 爸爸 is the kind of failure that a
   pronunciation score averages away and a listener does not. Either 6
   steps with a streaming change to cover the latency, or evidence that
   the control failures are an artefact of the two-character words.
2. **Sample rate and streaming.** VoxCPM2 emits 48 kHz against the
   resident 24 kHz, and the sidecar's chunked playback path is built
   around the current model's behaviour.

## What is not known

- **Intelligibility is not accent.** This measures whether a word survives,
  not whether it was said the Taiwan way. 企業 said as qǐ yè is still 企業
  to Whisper. The tone classifier in `sidecars/tone_probe` exists for that
  and is not yet trustworthy enough to quote — its controls scored 2/4.
- **Nobody has listened.** Thirty A/B pairs are in `~/Desktop/lulo-voice-ab`,
  named `word__candidate.wav`. Naturalness, pacing and whether it still
  sounds like the same person are not in any of these numbers.
- **Taiwanese Hokkien is unexplored.** VoxCPM2 advertises nine dialects
  including Hokkien, which is the one candidate here with a plausible path
  to it. Not tested.

## Rejected without testing

- **Cloud voices** (ElevenLabs, Azure, Google, MiniMax). Azure has real
  zh-TW voices and Hokkien, and every one of them means posting the user's
  conversation to a server. `BootstrapConfig.localOnly` is a promise this
  product makes; a better accent is not worth breaking it.
- **Kokoro** — cached and free to try, but it does not clone a voice, so
  adopting it means abandoning ryan.
