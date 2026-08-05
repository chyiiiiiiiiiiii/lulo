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

## What is not known

- **Twelve read recordings, one speaker.** The same caveat every measurement
  in this repo carries. Spontaneous speech is harder than read speech and
  nothing here says how either model behaves on it.
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
