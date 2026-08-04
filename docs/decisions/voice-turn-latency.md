# Where the wait between speaking and being answered actually goes

Status: measured; the prompt split is adopted, the endpointer is not moved.
2026-08-04. Measured on an M1 Pro (32 GB) against `gemma-4-E4B-it` on the
GPU backend and the resident Qwen3-TTS sidecar.

## The complaint, made falsifiable

"It should feel more like talking to someone." That is not actionable until
the wait is broken into the pieces a person sits through, and each piece is
timed on this machine with this model. Nothing in the pipeline measured
itself, so every previous opinion about which part was slow was an opinion.

## The budget, before

One warm turn in Taiwanese Mandarin — the user stops talking, and the first
sound of the answer comes back:

| Stage | Seconds | Who can see it |
|---|---|---|
| Silence the endpointer waits out, plus its 150 ms tick | 0.80–0.95 | `VoiceHostAdapter` |
| The transcriber answering `finalize(through: nil)` | not measured | nobody |
| Refinement, and the hop to the runtime | < 0.01 | `VoiceConversationController` |
| The model, to the first clause worth speaking | **1.95** | nobody |
| The synthesiser's first chunk | 0.48 | `~/dev/lulo-tts/server.log` |

The model's 1.95s was the surprise. It is not the model being slow.

## The prompt was being re-read on every turn

`composeAgentPrompt` built one block — personality, spoken-prose rules, user
preferences, developer instructions, this turn's memories, the question —
and the whole block went to the runtime as the user message. The stable half
is the same text every turn, so LiteRT-LM's KV cache, which extends by
appending, had to prefill it again with every question.

The same four-turn Mandarin conversation, same model, same content, differing
only in where the profile sits:

| Profile placement | Time to first token | To the first speakable clause |
|---|---|---|
| Inside every user message | 1.70–1.71s | 1.93–1.99s |
| `ConversationConfig.systemMessage`, prefilled once | 0.28–0.30s | 0.53–0.62s |

**1.4 seconds per turn**, for 157 characters of text that never changed.

The same comparison in English costs **nothing**: 0.27s inline against 0.26s
prefilled, for a profile that is twice as long in characters. Han is charged
several tokens a character where English is charged a fraction of one, so a
prompt shape that is free to re-read in English is not remotely free here.
That asymmetry is why this went unnoticed, and it is worth stating plainly:
**prompt cost measured in English says nothing about prompt cost in
Chinese.**

Measured in the app itself rather than a harness, through the real model and
the whole Dart-to-LiteRT path, by the real-model vertical slice:

| Turn | Before | After |
|---|---:|---:|
| Warm English | 344 ms | 343 ms |
| First Chinese, switching language | 1637 ms | 1580 ms |
| **Settled Chinese** | **1648 ms** | **362 ms** |

The slice used to ask only in English, which is why it could not see any of
this. It now asks in Chinese twice, because one Chinese turn is not the
steady state — see below.

So `AgentPromptContext` now arrives in two halves. `systemInstruction` is
what does not change between turns and is prefilled once; `turnInstruction`
is the memories this question made relevant plus the question itself.
`RuntimeGenerationRequest` carries them separately and the driver builds the
conversation with a system message.

A profile the user edits is a different system message, and a prefilled KV
cache cannot be amended. The driver notices and rebuilds the conversation,
re-seeding from stored history — one turn paying what every turn used to.

### The cost that moved rather than went away

`composeAgentPrompt` picks its language from the question, so the system
instruction is not stable across a language switch — and a changed system
instruction rebuilds the conversation. Measured in the slice above, the first
Chinese turn after an English one costs 1580 ms where the settled one costs
362 ms.

A question with any CJK character in it counts as Chinese, so ordinary
code-switching (「幫我看 Flutter 的版本」) is safe; only a wholly English
question inside a Chinese conversation, or the reverse, pays. Before this
change that turn cost 1637 ms anyway, so nothing regressed — but it is now
the only expensive turn left, and it is fixable by making the stable half
language-neutral instead of choosing between two translations of it.

## The endpointer stays at 0.8 seconds

The obvious next target was the 0.8s of silence. It survives, because the
measurement says shortening it would cut the user off.

Running `VoiceActivityBox`'s own algorithm over the twelve private corpus
recordings, the pauses *inside* an utterance are:

| Length | Where |
|---|---|
| 0.26s | most cases — clause boundaries |
| 0.51s | three cases |
| 0.77s | `endpoint-thinking-pause` |
| **1.02s** | `short-answer-not-yet` |

Mid-sentence pauses run *past* the 0.8s that submits the turn. The
distributions overlap, so no threshold on silence alone separates them —
which is what `needsContinuationGrace` and its hardcoded list of
「等一下」「我想問的是」「我想說的是」 have been quietly patching.

### Smart Turn v3.2 does not separate them either

That overlap is the exact problem semantic turn detection claims to solve,
so it was tested rather than assumed. Every pause in every case was
truncated 0.25s in — the moment a fast endpointer would have to decide — and
scored by `smart-turn-v3.2-cpu.onnx` through the same code path as
`sidecars/smart_turn_shadow`.

| Decision point | p(complete) |
|---|---|
| End of turn | 0.978–0.989 |
| Mid-sentence pause, ten of twelve | 0.973–0.988 |
| Mid-sentence pause, two of twelve | 0.107, 0.384 |

There is no threshold between them: at 0.95 it cuts the user off in ten of
twelve pauses, at 0.99 it never fires at all.

The instrument was checked before the result was believed. Cutting each
recording in the middle of a word — unambiguously an unfinished turn —
scores 0.98 as well, on eleven of twelve. The model is saturated on this
speech, not merely undecided, and the published figures agree about the
direction: Chinese is its weakest major language at 85.79% accuracy against
92.63% overall, with a 9.26% false-negative rate.

Twelve recordings is a small corpus and they are read rather than
spontaneous, so this is not a claim about Smart Turn in general. It is a
claim about whether it can be trusted to shorten *this* wait, and it cannot.

### What did move: the tick

The 0.8s threshold stays, but the endpointer only noticed it crossing at a
tick, and the tick was 150ms. That interval was added to every turn as pure
jitter on top of the largest item in the budget. It is now 50ms.

Nothing else changes with it. Every guard in `checkEndpoint` is a threshold,
so asking more often only finds the crossing sooner, and
`endpointFinalizeRequested` still means the transcriber is asked exactly once
per utterance. The calibration heartbeat divisor moved from 20 to 60 to keep
its ~3s cadence.

## The budget, after

| Stage | Before | After |
|---|---|---|
| Endpoint silence, plus its tick | 0.80–0.95 | 0.80–0.85 |
| The model, to the first clause worth speaking | 1.95 | **0.55** |
| Synthesiser's first chunk | 0.48 | unchanged |

About **1.5 seconds** off every turn, from a wait that was roughly 3.3s.

## What now measures itself

Two logs, each written by whoever can see the thing:

- `Lulo voice: final (23 chars) 0.31s after the ask` — the adapter, closing
  the one gap nothing could see: the transcriber answering the endpointer.
- `Lulo latency: refine 0.01s + think 0.29s + write 0.24s = 0.54s to the
  first 12 characters spoken` — `VoiceTurnLatency`, holding no transcript
  and no answer text, only lengths and instants.

With the adapter's existing `endpointing after 0.87s of silence` and the
sidecar's `render first-chunk 0.48s`, one turn is now accounted for end to
end without attaching a profiler.

## And separately: what the recogniser actually hears

Latency is not the only thing that had never been measured. Apple's
`SpeechAnalyzer`, driven over the same twelve recordings through the same
locale resolution the adapter uses, scores **14.6% spoken CER** — which is a
misleading headline, because half of it is the scorer and not the ear:

| Case | CER | What happened |
|---|---:|---|
| `numbers-money-version` | 61.5% | Heard correctly, written `12,000` and `3.5` where the corpus expects 一萬二 and 三點五 |
| `numbers-date-time` | 41.7% | Heard correctly, written `8月 2日下午 3:30` against 八月二日下午三點半 |
| `punctuation-natural-clauses` | 33.3% | Genuinely misheard: 細節我等等再補 → 細節我的忍在補 |
| `code-switch-product-names` | 18.2% | Flutter → Flater, MLX → NLX |
| `code-switch-agent-tools` | 10.5% | Dart test → Dortest |
| `disfluency-self-correction` | 7.7% | 欸 → 哎 |
| the other six | 0.0% | Exact |

Half the corpus comes back character-perfect, and the two worst cases are
not recognition errors at all — the recogniser writes digits and the corpus
spells them out. **`spokenCer` folds punctuation, whitespace and Latin case
but not numerals**, so any future ASR candidate is charged for a
disagreement about writing rather than hearing. That is a defect in
`benchmarks/voice_eval`, and until it is fixed the aggregate CER is a floor
on quality, not a measure of it.

The two code-switch cases are the ones the app already mitigates and this
measurement did not: `begin` hands the transcriber `contextualStrings` from
the conversation's vocabulary, which is exactly the remedy for Flutter
coming back as Flater. The probe passed no bias, so the app should do better
there than this table shows.

What is left after both caveats is one real failure in twelve. Locale
resolution is worth guarding, though: matching `zh-Hant-TW` by string prefix
instead of `SpeechTranscriber.supportedLocale(equivalentTo:)` selects zh-CN
and transcribes a Taiwanese speaker into Simplified. The adapter gets this
right; the probe got it wrong first and the difference was visible in one
glance at the output.

## Making it right rather than fast, and what that costs

The complaint that outlives the latency work is that the bubble shows a word
the user did not say. It is not a display bug: the recogniser writes 計算 for
肌酸, and the model's answer then says 肌酸, because the model has the
conversation and the recogniser does not.

### Hints do not help — measured

The obvious remedy is to tell the recogniser the words. `contextualStrings`
already carries a thirty-two term list, refreshed from every answer the agent
speaks. Run over the private corpus with the list and without it, **through
both the file path and the streaming path the app actually uses, the
transcript was identical to the character.** `Flater` stayed `Flater`, `NLX`
stayed `NLX`.

That is not proof the API does nothing — twelve clean recordings is a small
test, and a bias can only pick a term the acoustics already make plausible.
It is enough to say that nothing in the vocabulary book has ever been shown
to change a transcript, and that building further on it without measuring
first would be building on an assumption.

Two terms the agent talks about constantly were missing from the list
regardless: MLX and Codex. They are in it now.

### The recogniser already says which words it doubts

What does separate cleanly is the score the recogniser attaches to every span
and which nothing had ever read — `attributeOptions` was empty:

| Span | Confidence |
|---|---|
| Every correctly heard word in the corpus | 0.88–1.00 |
| `codex` (right, but unsure of the case) | 0.79 |
| `NLX` for MLX | 0.78 |
| `忍` in a misheard Mandarin clause | 0.69 |
| `Flater` for Flutter | 0.48 |
| `的` in the same misheard clause | 0.31 |

The signal is not language-specific and it is not subtle. A transcript is
reported as its weakest span rather than its average, because one bad word is
enough to make the sentence wrong and an average buries a 0.31 under a dozen
1.00s.

Requested and logged, nothing more. What to do about a low score is a
decision that needs its own evidence, and this is how it gets collected.

### What repair would cost, if it is wanted

Given the conversation, `gemma-4-E4B` repairs both real cases — 計算 and 記中
both back to 肌酸 — and leaves a correct sentence alone. On a scratch
conversation, so the real one never learns it was asked to proofread, that
costs 1.5–2.1s cold and an estimated 0.7–1.0s warm.

Smaller models do not substitute. Qwen3-0.6B and Qwen3-1.7B, both already on
the machine, returned the raw text unchanged for both cases. Given a few-shot
prompt they became worse rather than better: 1.7B rewrote 計算 into 乳清蛋白,
a different supplement from the same conversation, and 0.6B rewrote the
control — a sentence with nothing wrong with it — into Simplified. A
hallucinated correction is worse than a visible mishearing, so the cheap
model is not a cheaper version of this; it is a different, worse thing.

The choice this leaves is where the second is spent. Before the bubble, every
turn is correct and every turn is a second slower. After it, the turn is free
and the text corrects itself while the agent is already speaking. Gating on
the confidence above makes the expensive path rare, which is why the meter
went in first.

## The gate was green here and red everywhere else

Five steps had been failing in CI since before any of this work, and the
whole of the gate passed locally throughout. The causes were the same shape
every time — state that existed on this machine and not in the repository:

| Step | Standing on |
|---|---|
| workspace analysis, voice eval analysis | `benchmarks/voice_eval` was outside the pub workspace, so its package config existed only where someone had once run `dart pub get` there — and it is gitignored |
| Flutter tests | A check for Lulo, Flutter, Gemma and Qwen in the protected vocabulary, which lived only in a profile file on one developer's disk |
| macOS window tests | A resize asserted at 900x700; AppKit constrains a titled window to its screen, and the runner's is smaller |
| tone probe tests | numpy, installed here and nowhere in the workflow |

All four are fixed at the source rather than in the workflow: the package
joined the workspace, the vocabulary belongs to the product, the test asserts
the invariant instead of a number, and the dependency is declared. The gate
is green in CI now for the first time in the recent history of the branch.

## What was looked at and left alone

**The synthesiser serialising behind playback.** `/speak` ends in
`wait_for_drain()` on a single-threaded work loop, so the next sentence's
synthesis cannot start until the current one has finished playing — roughly
half a second of dead air at every chunk seam. It does not apply today:
full duplex uses `/render`, which returns when generation ends and lets the
app's own player node append gaplessly. It would return with the
half-duplex fallback.

**Answer length** — which turned out to be the largest number in this whole
document, and not a latency at all. Measured across five conversational
questions, answers averaged 172 characters: at the synthesiser's 0.156 s per
character, **twenty-seven seconds of speech**. Every second of that is a
second the user is not talking, and it dwarfs the 1.3s of first-token latency
this document opens with.

`回答長度：簡潔` was not an instruction. Replacing it with a sentence budget in
the spoken-response section — `回答控制在三句話以內；講完核心就停，細節等使用者追問再說` —
brought the average to 91 characters, about fourteen seconds, and shortened
every one of the five. Three of the five then ended by asking a question
back, which none of the long answers did. See
[../features/agent-profile.md](../features/agent-profile.md).

**`STREAM_INTERVAL = 0.8`.** The synthesiser's 0.48s first chunk is that
interval times its 0.6 real-time factor, so 0.5s would put the first sound
at roughly 0.30s. `0.4` was tried before and occasionally sent a sentence
into a babble loop; the values between are untested. The failure mode is
intermittent and destroys the answer, so it needs a stability run rather than
a guess, and it lives in another repository.

**A warm first turn.** Turn one costs 1.87s where later turns cost 0.29s,
because the system message and the restored history are prefilled then. The
model is already loaded at startup rather than on first prompt; prefilling
the conversation as well would move that cost off the first answer.
