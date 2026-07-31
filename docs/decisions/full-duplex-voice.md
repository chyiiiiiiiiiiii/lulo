# The microphone stays open while the agent talks

**Status:** accepted
**Decided:** `a84a2c4`, corrected and actually made to work at `7c9b36d`
**Supersedes:** [half-duplex-voice.md](half-duplex-voice.md) (`f4309e9`)

## The decision

Apple's voice processing is enabled on **both** the input and the output
node, and `fullDuplex` follows whether both were granted:

```swift
_ = engine.mainMixerNode          // must exist first; see -10875 below
try input.setVoiceProcessingEnabled(true)
try engine.outputNode.setVoiceProcessingEnabled(true)
```

On this hardware both are granted, so full duplex is the ordinary path: the
microphone is never muted, the VAD's clock never freezes, and the user can
talk over an answer and be heard mid-sentence. Half duplex — the mute, the
frozen clock, and the state machine that survives it — remains the fallback
wherever voice processing cannot be enabled.

**If the output refuses, the input is turned back off.** Input-only voice
processing is worse than none at all: the microphone stays open and nothing
removes the agent from it. That combination is not a degraded mode, it is the
bug this record exists to document. Both ends, or neither.

## The bug this cost us

For the whole life of the full-duplex work, voice processing was enabled on
the input node alone. The canceller lives in a single Voice-Processing I/O
unit that owns **both** ends of the audio; with the input alone, playback
still went out through a plain output unit, so the unit had no far-end
reference and there was nothing for it to subtract.

The symptom, measured in use:

```
partial (2 chars) peak 0.1443 floor 0.0021 WHILE SPEAKING
  "Fl" → yield speaking=true cancelsGeneration=TRUE
  "Flonter Google的這個技"
```

Nineteen partial transcripts in one session, arriving while the agent was
speaking, spelling out the agent's own sentence about Flutter and Google.
Peak 0.1443 against a 0.0021 noise floor — roughly seventy times the floor,
a full speaking voice, not a residue.

Because one non-empty partial cancelled the whole answer, and because a
cancelled answer is never spoken, **the agent talked itself into silence and
stayed there.** The user saw text arriving with no voice, asked why, and
their own question then cancelled the next answer too.

## Three measurements, and why the first two were wrong

| | Method | Conclusion | The error |
|---|---|---|---|
| `f4309e9` | `afplay` through the speakers as a stand-in for a person | "the microphone goes deaf" | Suppressing loudspeaker audio is exactly what a voice-processing unit is for. It measured the canceller working and read it as deafness. |
| `a84a2c4` | A real voice, comparing VP on (0.1798) against off (0.1743) | "the canceller works, full duplex is back" | It measured that the microphone is **not deaf**. That is a different claim from "the agent's own voice is removed". |
| `7c9b36d` | Play the app's own voice; read what the transcriber receives | "it is transcribing itself" | — |

**The first two both measured the near end** — whether the microphone can
still hear a person — and neither ever tested the far-end subtraction, which
is the entire definition of an echo canceller. The third test is the obvious
one in hindsight, and it was never run deliberately: it fell out of using the
app and looking at a log.

**The method lesson is the durable one: when testing an echo canceller, a
loudspeaker is not a stand-in for a voice, and a microphone that still hears
is not proof that anything was cancelled.** The only valid test plays the
system's own output and asks what survived downstream.

A fourth trap, on the same theme, caught the verification of the fix itself.
`WHILE SPEAKING` partials went from 19 to **28** after the repair, which
looks like a regression and is not: with full duplex working, a user talking
over the agent *should* produce partials while speaking — that is the
feature. The count says nothing; **the content does.** Before, it was the
agent's sentence; after, it is the user's.

## What survived from the old decision

**`kAUInitialize -10875` is real and its cause still holds.** A
`mainMixerNode` instantiated *after* voice processing reshapes the graph
lands on 44.1 kHz against 48 kHz hardware, and the output unit refuses to
initialize as soon as a player node is attached. Six trials pinned it down,
and only the ones touching the mixer first started. So
`_ = engine.mainMixerNode` comes before either `setVoiceProcessingEnabled`
call, and that ordering is load-bearing.

Note what this means for the old record's six trials: "input and output"
*was* among them, and it failed — but it was tried **before** the mixer
ordering was understood. The combination that works here, mixer first and
both ends enabled, had never been tried until now.

The two `speakableText` fixes from that work also stand: no
system-synthesizer fallback, and horizontal rules and list bullets stripped.

## What full duplex costs

Barge-in stopped being a rare path and became the everyday one, which
promoted a set of latent defects from theoretical to daily:

- An unacknowledged cancellation read as a failure, thrown at callers that
  could not catch it, leaving the send key dead (`123e632`).
- A fenced start still sent to the runtime, orphaning a generation that held
  the single native slot until it burned its whole token budget (`123e632`).
- One character enough to interrupt, so "OK" ended an answer 571 characters
  into being read aloud (`2c88ca2`).
- An interrupted sentence never said again, because the dispatch counter
  records what was handed to the voice rather than what was heard
  (`2c88ca2`).

That is the shape of the cost to expect. Full duplex does not add failures;
it makes existing ones happen every day.

The half-duplex state machine — `outstandingUtterances`, `unmuteGeneration`,
`speakingReported`, `muteLiftedAt`, the 300 ms hangover — is still needed for
the fallback path and still described in
[../features/voice.md](../features/voice.md). `utteranceEnded`'s
`if !self.fullDuplex` branch is the piece to read first when touching any of
it: full duplex never mutes and never freezes the clock, so it must not reset
an utterance the user is in the middle of.
