# The first answer is already as warm as it gets

The first question of a session takes noticeably longer to answer than the
ones after it. This is where that time goes, and why the obvious fix — warm
the model up with a throwaway generation, the way the audio engine is warmed
— buys back nothing.

## What the first answer costs

`FirstReplyLatencyTests` times each phase against the real gemma-4-E4B on the
backend the app actually runs (`.gpu` on arm64) and its own cache directory:

| | |
|---|---|
| `Engine(engineConfig:)` | 0 ms |
| `engine.initialize()` | **3679–8508 ms** |
| `createConversation(systemMessage:)` | 1 ms |
| turn 1, first token | **1505 ms** |
| turn 1, whole answer | 1968 ms |
| turn 2, first token | **254 ms** |
| turn 2, whole answer | 680 ms |

Two separate costs, and only one of them is the first *answer's*.

**Loading is the big one and it is already off the critical path.**
`bootstrap.dart` calls `warmUp()` at launch precisely so nobody waits for it.
A user who asks a question within the first few seconds of launching still
waits for it, because it has not finished — but that is a question of saying
so, not of making it faster.

**The first turn then pays about 1.25 s more than a settled one**, and that is
the preface prefill. `voice-turn-latency.md` priced the same thing at 1648 ms
against 362 for a settled turn, which is what split `AgentPromptContext` into
a `systemInstruction` prefilled once and a `turnInstruction` read every time.
This measurement reproduces it: 1505 against 254, with the conversation
holding 207 tokens of which the preface is most.

`createConversation` is 1 ms, so it does not prefill. The prefill happens
inside the first `sendMessageStream`.

## Why warming it up does not help

The idea was the audio engine's: build the expensive thing at launch so the
press costs nothing. Measured both ways **inside one process**, so they share
a page-cache state:

| | first token |
|---|---|
| no warm-up generation | 1505 ms / 1573 ms |
| one throwaway generation first | 1523 ms / 1700 ms |

Identical, or slightly worse. There is nothing left for a warm-up to page in:
`initialize()` has already done it, and the 1.25 s is arithmetic over the
preface, which is different text every session and cannot be done in advance
by generating something else.

**And it cannot be prefilled ahead of time either.** The vendored
`Conversation` exposes no prefill: `sendMessage` and `sendMessageStream` are
the only ways in, and both leave a turn in the conversation that nobody said.
Pre-creating the conversation is free and already effectively happens; there
is no API to make it warm. This is the same shape of gap as constrained
decoding in `tool-calling-readiness.md` — the upstream runtime may have it,
the copy in `native/vendor/litert_lm/swift/` does not.

## How this measurement went wrong first, and what that cost

The first run of this probe reported **13027 ms** for the first token and
**6825 ms** after a warm-up generation, which reads as the warm-up halving it.
Every part of that was an artifact:

- It ran on **`.cpu`**. `LiteRTLMRuntimeConfiguration.defaultBackend` is
  `.gpu` on arm64, so the number described a configuration this app never
  runs. On the real one the same measurement is 1505 ms.
- The two figures came from **two separate processes**, the second with a page
  cache the first had warmed — visible in `initialize()` dropping from 1027 ms
  to 321 between them.
- So the comparison differed in the backend, the cache state, and the thing
  being tested, and was attributed entirely to the third.

The probe now runs both variants in one process, on the app's backend, and
prints them next to each other. It carries no assertion: there is no
threshold here that means anything, and what is worth keeping is the two
numbers taken the same way, for the next person who has this idea.

## Where a warm-up cost is worth measuring, and where it is not

The audio engine's warm-up is the same idea applied to something it does
work on, and its numbers are worth keeping beside these because they were
taken in three places and only one of them was the app:

| | first `makeWarmEngine()` |
|---|---|
| bare `swift` script | 1098 ms |
| XCTest host, with the app's own warm-up also running | **86 s** |
| XCTest host, once the app's warm-up is guarded off | 5.5 s |
| **the real app** | **1077 ms** |

The 86 seconds was two engines being built at once — the test host *is* the
app, so its `VoiceHostAdapter.init` was warming one up beside the one the
test was building, and they contended. Guarding the warm-up off under
XCTest removed it. The 5.5 s that remained is the first CoreAudio touch in
that process, and it is not the app's number either.

So a measurement taken in the test host said 86 s, then 5.5 s, for something
the app does in 1.08 s. Neither was wrong about what it measured; both were
wrong about what they were taken to mean.

## What is left worth doing

Not making the first answer faster — 1.25 s of preface prefill is the price
of the preface, and the way to lower it is a shorter preface, which costs the
persona and the spoken-answer rules.

What is left is **saying so**. A question asked while `initialize()` is still
running waits several seconds with nothing to explain it, and that wait is
indistinguishable from a hang. The menu bar already carries an `activity`
line pushed from Dart; the model's readiness is the one thing it does not
say.
