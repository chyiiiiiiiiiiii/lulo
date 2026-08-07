# Which recogniser answers the push-to-talk key

Status: measured; Breeze-ASR-25 adopted for the batch path. 2026-08-05,
over `benchmarks/voice_eval/corpus/zh-TW-v1.json` on an M1 Pro.

## Two recognisers, and only one of them is being replaced

Lulo hears through two, for two different jobs:

| Path | Model | Why it is that one |
|---|---|---|
| Streaming, drives the endpointer | Apple `SpeechAnalyzer` | The only one that emits partials while the user is still talking |
| Batch, answers the hold key | `mlx-community/whisper-large-v3-turbo` in `~/dev/lulo-tts/ears.py` | Release is the endpoint, so nothing needs partials and accuracy is free to cost a second |

Everything below is about the **batch** one. The Whisper family cannot
stream, so none of it is a candidate for the other path, and the endpointer
work in [turn-taking-by-words.md](turn-taking-by-words.md) is unaffected.

## Why Breeze-ASR-25 was the one worth trying

[voice-turn-latency.md](voice-turn-latency.md) measured Apple's streaming
recogniser at 14.6% spoken CER and found the two worst genuine errors were
both code-switching — `Flutter → Flater`, `MLX → NLX`, `Dart test →
Dortest`. `MediaTek-Research/Breeze-ASR-25` is a Whisper-large-v2 fine-tune
whose stated purpose is Taiwanese Mandarin and Mandarin-English
code-switching. That is an unusually exact match to a measured failure, which
is the only reason it jumped the queue ahead of larger models.

Run through `Kenji8000/Breeze-ASR-25-mlx` (3.08 GB fp16), against the
incumbent, both through the same post-processing `ears.py` applies and the
same protected vocabulary, by `benchmarks/voice_eval/tool/asr_probe.py`.

## The result

| | Heard CER | Spoken CER | Character-perfect |
|---|---:|---:|---:|
| `whisper-large-v3-turbo` (incumbent) | 3.1% | 10.3% | 9/12 |
| **`Breeze-ASR-25`** | **1.6%** | **8.6%** | **10/12** |

Read `heardCer` first: it is spoken CER with every number removed from both
sides, so it answers "did it hear the words" where spoken CER also charges
for how numbers are written. See
[../../benchmarks/voice_eval/README.md](../../benchmarks/voice_eval/README.md).

Where they differ, which matters more than the means over twelve cases:

| Case | Incumbent | Breeze |
|---|---|---|
| `punctuation-natural-clauses` | 細節**無論論**再補 — 25% | 細節**我等等**再補 — **0%** |
| `disfluency-self-correction` | 我想看明天**___**不是… — 7.7%, the filler deleted | 我想看明天**欸**不是… — **0%** |
| `barge-in-stop-answer` | 先不要**念**完 — 0% | 先不要**唸**完 — 14.3% |
| `code-switch-product-names` | Flutter 和 MLX — 4.5% | Flutter 和 MLX — 4.5% |

The first is the one genuine mishearing in the whole corpus and Breeze is the
first recogniser measured here to get it right — Apple wrote 細節我的忍在補,
the incumbent wrote 無論論. The second matters more than its number says:
the corpus note on that case is "a correction whose original words must
remain in raw ASR", and deleting the 欸 is deleting the evidence.

Both wrote 和 where the corpus says 跟, identically. A shared error across
two unrelated models is more likely to be the corpus than the recognisers,
and it is left alone rather than quietly excused.

**Breeze's only remaining error is not a mishearing.** 唸 and 念 are both
correct Traditional forms of the same word. Folding character variants the
way numbers are folded would take Breeze to 11/12 — and it is deliberately
not done, because choosing a new normalisation *after seeing which candidate
it flatters* is how a benchmark stops meaning anything. If variant folding is
wanted it should be argued for on its own and applied to whatever is measured
next.

## What the measurement cost, and what it fixed

The first scoring had Breeze **losing** on `numbers-date-time` at 28.6% heard
CER. It had heard the time perfectly. Breeze writes 「3 點半」 with spaces
where the corpus writes 「三點半」 without, and `normalizeHeard` did not treat
whitespace as part of a number — so 點半 folded on one side and survived on
the other. Whitespace is a joiner now, and the test that says so quotes both
spellings.

That defect was written this morning and would have shipped unnoticed if the
only thing ever scored had been a recogniser that writes numbers without
spaces. A second candidate is what found it.

## Speed and size

| | Per utterance | RTF | Resident |
|---|---:|---:|---:|
| `whisper-large-v3-turbo` | 0.88–1.01s | ~0.19 | ~1.6 GB |
| `Breeze-ASR-25` | 1.07–1.85s | ~0.25 | ~3.1 GB |

About 30% slower and twice the memory, for a held utterance that the user has
already finished speaking. The hold key's answer arrives in roughly 1.3s
where it took 1.0s, against an ASR the batch path exists to be more accurate
than. That trade is why this path is batch in the first place.

## English, through the same key

Added 2026-08-06, because the question the corpus above could not answer was
whether a wholly English sentence survives a path pinned to Chinese.
`ears.py:62` passes `language="zh"` to every transcription, so "can Breeze
hear English" and "can the shipped configuration hear English" are two
questions.

Eight English utterances, `corpus/en-synthetic-v1.json`, scored the same way:

| | Spoken CER | Literal CER | Per utterance |
|---|---:|---:|---:|
| **`Breeze-ASR-25`, `language=zh`** — what ships | **0.0%** | 0.8% | 1.16–1.27s |
| `Breeze-ASR-25`, `language=auto` | 0.0% | 0.8% | 1.96–2.09s |
| `whisper-large-v3-turbo`, `language=zh` | 48.6% | 44.8% | 0.82–**8.66s** |

Breeze is character-perfect on all eight **while being told the audio is
Chinese**. The 0.8% literal CER is punctuation and nothing else — one comma
where a full stop was read, one missing final stop. It spells `LiteRT` and
`Dart test` correctly, which are two of the three code-switching errors that
sent us looking for it in the first place.

The incumbent is not merely worse, it is dangerous at this: `Can you explain
what the LiteRT runtime does?` came back as 「可你解釋什麼LiteRT runtime?」, and
`Open the settings and turn the voice off` collapsed into a degenerate loop —
「開啟鼓鼓鼓鼓…」 for **8.66 seconds** against 0.86s for every other case. A
recogniser forced into the wrong language does not fail gracefully; it fails
slowly.

Two things follow.

**Nothing needs building for English on the hold key.** It already works, on
the model already installed, in the configuration already shipping. What is
missing is that a user has no way to know the hold key hears English while
the streaming path does not.

**Do not switch to `language="auto"`.** It buys nothing here — identical
transcripts — and costs about 60% more time per utterance, because detection
is its own pass. The pinned language is both more accurate on Chinese and
faster on English.

### Read by a person, all sixteen

Added the same day. The eight above were `say` output and a synthesizer
flatters a recogniser, so the whole corpus was read aloud by one speaker and
run through the shipped configuration.

| | Spoken CER | Heard CER |
|---|---:|---:|
| Synthesized, eight cases | 0.0% | 0.0% |
| **Spoken, sixteen cases** | **6.8%** | **3.8%** |
| *For comparison:* `zh-TW-v1`, spoken | 8.6% | 1.6% |

Nine of the sixteen are character-perfect. English on this path is usable and
it is **measurably worse than Chinese** — 3.8% heard against 1.6% — on the
same model in the same configuration. That is the honest headline, and it is
not what the synthetic run suggested.

Three things the synthesizer could not have told us, and all three are good
news:

- **`spoken-restart` scores 0.0%.** `Can you — actually, can you show me the
  last three commits instead?` came back with every word, self-correction
  included. Spontaneous-speech disfluency is the standing caveat on every
  corpus in this repo and this is the first evidence about it.
- **`spoken-short` scores 0.0%.** A one-word `Stop.` survives, which is the
  shortest thing anyone says to this app.
- **`spoken-vocabulary` scores 0.0%** with `Gemma`, `LiteRT` and `MLX` in one
  breath.

What actually fails is one thing, twice:

| Case | Read | Heard | Heard CER |
|---|---|---|---:|
| `spoken-dart-test` | **Dart test** is failing on the second case. | **Dark text** is falling on the second cast. | 12.5% |
| `spoken-tooling` | Open Xcode and run the **Swift tests** | Open Xcode and run the **sweep test** | 7.4% |
| `spoken-numbers` | and **the gate** has 21 steps | and **again** has 21 steps | 20.0% |
| `spoken-code-switch-out` | not **the** model | not **a** model | 8.8% |
| `spoken-filler` | So, **um**, … keeps **failing** | So, … keeps **falling** | 7.3% |
| `spoken-run-tests` | run the **tests** | run the **test** | 3.3% |
| `spoken-long-pause` | which **recogniser** | which **recognizer** | 1.7% |

**A product name that is also an ordinary English word is the failure mode.**
`swift`, `dart`, `test`, `case` are all real words, so a vocabulary list
cannot disambiguate them by spelling — and `Dart test` came back correct in
`spoken-tooling` and wrong in `spoken-dart-test`, the same term in two
contexts. Nothing here fixes that; it is the residue after everything that
can be fixed has been.

The last one is arguably the corpus's fault rather than the recogniser's:
`recogniser` against `recognizer` is a spelling convention, and the scorer
cannot know which was intended.

### The heard score could not see English numbers

`spoken-numbers` first scored **67.2% heard CER** — against a transcript that
had heard everything but one word. `normalizeHeard` removes numbers from both
sides so that a disagreement about *writing* a number is not charged as a
mishearing, and its numeral class covered digits and CJK numerals because
until now every corpus was zh-TW. English writes numbers as words, so
`twenty-one` stayed while `21` was removed and the fold ran exactly backwards.

The class now names the English number words too. Scored again, that case is
**20.0%** — the `the gate` → `again` error, and nothing else. The zh-TW
evidence re-scores to 8.6% / 1.6% and 10.3% / 3.1%, unchanged to the digit,
so the change is inert on the corpus it was not written for.

This is the same repair as the 「3 點半」 one above, in the other script, found
the same way: a case that scored badly against a transcript that was right.

### The vocabulary prompt is load-bearing here, and only here

Ablated on these recordings, `held_prompt(TERMS)` changes **exactly one
transcript** and leaves the other seven byte-identical:

| | With vocabulary | Without |
|---|---|---|
| `spoken-litert` | Can you explain what the **LiteRT** runtime does? | Can you explain what the **light RT** runtime does? |

That reads as a contradiction of [voice-turn-latency.md](voice-turn-latency.md)'s
"Hints do not help — measured" and is not one. That measurement was of
Apple's `contextualStrings` on the **streaming** path. This is Whisper's
`initial_prompt` on the **batch** path — a different mechanism on a different
recogniser, and here it is the difference between a product name and two
ordinary words. The vocabulary book is inert on one path and load-bearing on
the other, and both statements are measured.

All four runs are checked in under
`evidence/english-through-the-hold-key/`.

## What is not known

- **Twelve read recordings, one speaker.** The same caveat every measurement
  in this repo carries. Spontaneous speech is harder than read speech and
  nothing here says how either model behaves on it.
- **One speaker, sixteen sentences, read aloud.** The same caveat every
  measurement in this repo carries. Two of the sixteen were written to sound
  spontaneous — a self-correction and a filler — and being asked to read a
  disfluency is not the same as producing one.
- **Nothing about accent.** One Taiwanese speaker of English. A recogniser's
  behaviour across accents is a different question and this does not touch
  it.
- **Nothing was measured about the streaming path in English.** It is Apple's
  `SpeechTranscriber` at one locale chosen in `begin()`, and that locale is
  the user's, so a wholly English sentence there is transcribed by a
  recogniser set to Chinese. Nothing above applies to it.
- **Breeze writes no punctuation.** Harmless on this path — release is the
  endpoint, so nothing downstream reads a full stop — but it would matter if
  this model were ever put behind the streaming path, where `TurnCompletion`
  reads terminal punctuation as a completion cue.
- **Breeze lower-cases Latin** (`codex`, `dart test`). The deterministic
  transcript refiner already treats vocabulary casing as a permitted edit, so
  this is repaired downstream rather than by the recogniser — but that path is
  now load-bearing where it was not before.
- **Nothing was measured about Taiwanese Hokkien.**
  `MediaTek-Research/Breeze-ASR-26` (BreezeASR-Taigi) reports 30.13% CER on
  the Taigi benchmark against 49.99% for this model, but it is a different
  question from the one this document answers, and
  [taiwan-mandarin-voice-candidates.md](taiwan-mandarin-voice-candidates.md)
  closed the Hokkien question on **synthesis**, which this does not reopen.
