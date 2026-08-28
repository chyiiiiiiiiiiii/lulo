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

## Tone, separately

"Did the word survive" is binary and hides how it failed. Reading the
transcript back as pinyin scores every syllable twice — once for the sound
and once for the tone on it:

| Candidate | Syllable sound | Tone | Right sound, wrong tone |
|---|---|---|---|
| Qwen3-TTS (resident) | 79% | 73% | 4 |
| VoxCPM2, 10 steps | 95% | 91% | 3 |
| VoxCPM2, 4 steps | 90% | 87% | 2 |
| IndexTTS-1.5 | — | — | 36 of 37 unalignable |

The last column is the surprise. The complaint was about tone, and tone
alone accounts for four errors out of thirty-seven words. The rest are not
a tone slipping — they are a different syllable entirely, which is why
Whisper writes 奇幼 and not 企業. What is heard as "slightly wrong tone" is
mostly the voice saying another word and the listener's ear repairing it
far enough to notice something is off without noticing what.

That matters for the fix: better tone modelling would not have helped. A
model that gets the syllable right is what was needed.

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

## Then the probes were checked against real sentences, and the case collapsed

Eight sentences of the kind this agent actually speaks — forty characters
each, carrying the same failing words — rendered by both and transcribed
back:

| Candidate | Mean CER | RTF over the set |
|---|---|---|
| Qwen3-TTS (resident) | 0.093 | 0.52 |
| VoxCPM2, 4 steps | 0.087 | 1.02 |

Six tenths of a point apart. Nothing like 73% against 89%.

The probes overstate the difference, and it is worth being precise about
why, because the same trap is waiting for the next measurement. A probe is
one word inside a seven-character carrier. That is a short, contextless
utterance, and a model that predicts sound from surrounding text has
almost nothing to predict from. Given a real sentence, the resident voice
says 企業 correctly — the very word it destroys in the carrier.

So the probe measures a real weakness under the least favourable
conditions, and real speech is more favourable than that. It remains the
right instrument for ranking pronunciation, and a bad instrument for
estimating how much better a voice will sound.

The failures also differ in kind, which an average hides. The resident
voice is consistently a little wrong: 確認 as 誇引, 編譯 as 偏系, 品質 as
品級, 危險 as 一會兒. VoxCPM2 is usually cleaner and occasionally
catastrophic — one sentence in eight came back as 斜周賽開抵抗試試 where
成長最快 was asked for, a CER of 0.32 in a set averaging 0.087, and
編譯 rendered as the English "Penid". A voice that is reliably slightly
wrong may well be preferable to one that is usually right and sometimes
unintelligible, and that is a judgement about the product, not a number.

## Recommendation

**Do not swap yet.** The evidence that justified a swap does not survive
contact with real sentences: a six-tenths-of-a-point CER improvement does
not pay for doubling the time to speak, and this machine also has Gemma on
it. Every RTF here was measured with the TTS alone; in use it shares an M1
Pro with the model generating the words it is about to say, so 1.02 is
optimistic and 0.52 is the margin that makes the current voice feel
immediate.

### Quantisation is not the cause — tested and refused

The cheapest possible fix would have been the same model without the
8-bit quantisation: same voice, same integration, no product risk.

`Qwen3-TTS-12Hz-0.6B-Base-bf16` scores **26/37 — 70%**, against the 8-bit
build's 27/37. That is noise, not an improvement; the two lose slightly
different words (bf16 says 企業 correctly and loses 垃圾 and 媽媽, which
the 8-bit build gets right) and the same number overall.

So the mispronunciation is in the model, not in its compression. Nothing
is to be gained by shipping the larger weights, and the possibility is now
closed rather than left hanging as an untested hope.

(Its RTF of 2.14 is not comparable to the 8-bit 0.60: this run went
through mlx-audio cold while the baseline is a warm resident server. Speed
was not what the experiment was asking.)

### What did fix it: spell the word as a different word

Every avenue above assumed the answer was a better model. It was not.

Writing 氣業 makes the voice say qì yè, which is what 企業 is. The
recogniser, given audio synthesised from 氣業, writes back 企業 — the sound
was right enough for a language model to prefer the real word, which is the
evidence that it was right.

Ten of the eleven measured failures are fixed this way. On whole sentences:

| Sentence | Before | After |
|---|---|---|
| 危險的操作… | CER 0.214 | 0.111 |
| 品質跟速度… | 0.077 | 0.038 |
| 成長最快的… | 0.074 | 0.019 |
| 好的，我幫你確認… | 0.122 | 0.122 |

The last row is the control and the useful one: 結構 was already correct in
that sentence, and the remaining error was 確認, absent from the table at
the time. The substitution changes what it was measured on and nothing
else.

Shipped as `sidecars/pronunciation`, applied between the text and the
synthesiser and nowhere else — the conversation, the stored turn and the
screen all keep the real spelling. No model change, no speed cost, and the
table records the defect each entry fixes so it can be deleted when a
future model no longer needs it.

### The table the user can reach

The eleven entries above are the ones measured here. They are not the ones
somebody will hit next, and adding to them meant editing a Python file in
this repository and restarting a sidecar — while the mirror-image repair for
the *recogniser*, `AgentProfile.misheard`, has been editable in Settings and
live on the next turn all along. That asymmetry was the actual complaint the
next time a word came out wrong.

`AgentProfile.respellings` closes it. Same shape of control, in the same
section of the same sheet, applied in `PigeonVoiceService.speak` — the single
place text leaves for the voice, and deliberately the last thing that happens
to a sentence. The sidecar's built-in table stays where it is as the floor;
the user's runs first, so teaching a word overrides the shipped entry for it
rather than fighting it.

Two things a reader should know before extending this. The substitution runs
on `applyMisheardWords` rather than on a second implementation, because it is
the same problem — longest rule first, nothing one rule writes read by the
next, graphemes not code units — and every one of those properties is already
pinned by a test there. And **"same sound, always" is not enforceable in
code**: an entry that changes the sound is the voice saying a different word,
which is worse than the defect it replaces because it is invisible in text.
`sidecars/tone_probe` is how an entry gets verified; the editor cannot do it,
so the note under the field says what the field is for and the responsibility
stays with whoever types in it.

### What the evidence does support

**Listen before deciding anything else.** Naturalness, pacing, and whether
it still sounds like the same person are in none of these numbers, and they
are most of what the complaint was about. The measurements have gone as far
as they usefully can without an ear. Thirty A/B word pairs and sixteen
sentence pairs were rendered for that and have since been deleted;
`~/dev/lulo-tts/render_probes.py` and `sentence_run.py` make them again
while the candidate models stay cached.

The respelling table makes a swap less urgent rather than unnecessary: it
fixes the words it was measured against, and does nothing for the next word
nobody has hit yet.

If a swap does happen later, two things are unresolved: VoxCPM2 emits
48 kHz against the resident 24 kHz, and its occasional catastrophic
sentence needs a bound before it is allowed to speak to a user.

## What is not known

- **Intelligibility is not accent.** This measures whether a word survives,
  not whether it was said the Taiwan way. 企業 said as qǐ yè is still 企業
  to Whisper. The tone classifier in `sidecars/tone_probe` exists for that
  and is not yet trustworthy enough to quote — its controls scored 2/4.
- **Nobody has listened to the Mandarin pairs.** Naturalness, pacing and
  whether it still sounds like the same person are not in any of these
  numbers, and the thirty A/B renders they would be judged from have been
  deleted. They are reproducible from `~/dev/lulo-tts/render_probes.py`
  while the candidate models stay cached; the raw per-probe results are
  kept in
  [`../../benchmarks/voice_eval/evidence/taiwan-mandarin-voice-candidates/`](../../benchmarks/voice_eval/evidence/taiwan-mandarin-voice-candidates/).

### Taiwanese Hokkien: judged, and it does not work

VoxCPM2 lists nine Chinese dialects including 閩南話, and four Taiwanese
sentences written in Han characters were rendered to find out whether that
was real. A Mandarin recogniser is no help here and none of the measurements
in this document apply, so it needed a speaker.

**2026-08-04, judged by ear: bad.** That closes the one open question that
could have outweighed the Mandarin result — VoxCPM2 being the only candidate
with any route to Hokkien was worth more than 0.6 percentage points of CER,
and it turns out not to have the route.

Not measured further, because there is nothing to measure: a listener who
speaks the language said it does not work, and no CER over a Mandarin
recogniser would have been able to say otherwise.

## Rejected without testing

- **Cloud voices** (ElevenLabs, Azure, Google, MiniMax). Azure has real
  zh-TW voices and Hokkien, and every one of them means posting the user's
  conversation to a server. `BootstrapConfig.localOnly` is a promise this
  product makes; a better accent is not worth breaking it.
- **Kokoro** — cached and free to try, but it does not clone a voice, so
  adopting it means abandoning ryan.
