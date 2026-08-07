# Dictation cannot share the conversation's microphone

Hold a key anywhere in macOS, speak, release, and have the words land on the
clipboard. Lulo already has every piece: a background-capable Carbon hotkey
with press and release events, a buffer that records held speech, a batch
recogniser that turns it into text in about 1.3 seconds, and a clipboard
that needs no entitlement to write.

It was built, reviewed twice, and taken back out. This is why, so that the
next attempt starts from the right shape instead of this one.

## What was built

A native-only path: hotkey down → buffer audio → sidecar → `NSPasteboard`.
Deliberately never touching the conversation, because the transcript must
not stop an answer being written, take the agent's turn, or reappear as a
question somebody asked. Keeping it out of Dart entirely makes all three
structurally impossible rather than merely handled.

That part was right. What was wrong was where the audio came from.

## Why it failed

The held-speech buffer is fed from the microphone tap **inside the
conversation's listening session**. So dictation had to carve a mode out of
a tap that is already serving a live, stateful, real-time pipeline: voice
activity detection, an endpointer running on a 50 ms tick, a half-duplex
mute, and a streaming analyzer. Every attempt to carve that mode out created
a new interaction bug somewhere else in it.

Two rounds of review. The first found that with voice on, the same audio
still reached the analyzer, so a dictation submitted a question and took the
floor — all three forbidden things, in the only configuration where the
feature worked at all. The fix was a guard in the tap: while dictating,
route the samples to the dictation buffer and yield nothing.

The second round found that the fix made things worse in two places.

**Skipping the VAD accelerated the endpointer instead of stopping it.**
`vad.observe` no longer ran, so `lastVoice` froze, so the silence measured
against it grew without bound while the key was held. The endpoint check
kept ticking, found an utterance in progress and enough silence, and
finalized the audio already inside the analyzer. Pressing the dictation key
mid-sentence therefore submitted the truncated half-sentence and started the
agent talking — into the dictation. The guard stopped *new* audio reaching
the analyzer and did nothing about audio already in it.

**Letting dictation through the half-duplex mute recorded the agent's own
voice.** The mute is only ever set in the one mode with no echo canceller,
where the answer is played by an out-of-process sidecar and nothing
subtracts it from the input. So the bypass fired exclusively where it was
unsafe, and put the agent's own sentence on the clipboard — reported as
success.

Two more, both regressions to code that already worked. Nothing reset the
dictation buffer on session teardown, so a hold whose release Carbon never
delivered would leave it active and route every subsequent buffer away from
the analyzer: the conversation goes deaf, silently. And making
`HeldSpeechCaptureBox.begin()` refuse when already active — a key-repeat
guard dictation needed — cost push-to-talk its only recovery from exactly
that dropped release.

## What the next attempt should do

**Give dictation its own `AVAudioEngine` and its own tap.** Not a mode
inside the conversation's tap. The failures above are all one failure: two
features sharing one real-time audio path and one set of timers, where the
timers belong to the other feature. A separate engine has no VAD to freeze,
no endpointer to mislead, no mute to bypass, and no shared buffer to reset.

It also removes the constraint that made the feature nearly useless anyway —
that the microphone had to already be open, so dictation only worked when
the user had already switched voice on.

Things the built version got right and worth keeping:

- Native-only, so the transcript cannot reach the conversation by accident.
- Distinguishing "the recogniser is not running" from "it heard nothing"
  from "the ears were never open". Three failures, three different fixes;
  one message sends the user to do the two things that cannot help.
- Reporting the outcome in the **menu bar**, with a sound on failure. The
  user is by definition working in another app, so anything drawn inside
  Lulo's own window is drawn where nobody is looking. A failure that is only
  logged is discovered by pasting the previous clipboard contents into
  somebody else's document.
- Not taking ⌘⇧D. Finder, Mail and most editors use it, and a Carbon hotkey
  beats the frontmost app's menu — registering it breaks those apps for as
  long as Lulo runs. Neither hotkey being user-configurable is the real
  problem underneath that, and is still not solved.

## The plan for the next attempt, and the answer to the one thing to check first

**Two `AVAudioEngine`s can coexist. The plan below stands.** Measured
2026-08-07 20:21: `SecondAudioEngineTests` passes in **2.4s**, both taps
receiving buffers. A standalone script outside XCTest agrees, three runs out
of three, at 48 kHz mono with 22 and 20 buffers arriving in two seconds. The
question the rest of this document rests on is closed.

```sh
cd apps/local_agent_macos/macos
TEST_RUNNER_LULO_AUDIO_DEVICE_TESTS=1 xcodebuild test \
  -workspace Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination platform=macOS \
  -derivedDataPath ../build/macos_window_tests \
  -only-testing:RunnerTests/SecondAudioEngineTests
```

### Two wrong explanations for a hang that was environmental

The answer above took three tries to get, and the two failed ones are worth
keeping because both were confident and both sent the next person somewhere
useless.

**The first** said the run needs somebody at the machine to dismiss a TCC
prompt. That was a guess from watching an `xcodebuild` hang. Measured on
2026-08-07 it does not survive:

- With the environment variable set, the run hangs **three times out of
  three** — 19 minutes, 7 minutes, and a third killed at 4. It stops after
  `RegisterWithLaunchServices`, with the test host launched and idle at 0.4%
  CPU. `Testing started` never prints, so it is not hanging *inside* the test.
- The same command **without** the variable, so the test takes its `XCTSkip`,
  passes in **1.9s**. `-only-testing:RunnerTests/DesktopPanelControllerTests`
  passes in **4.5s**. The test host and the workspace are fine.
- There is **no dialog**. `log show --predicate 'process == "tccd"'` has no
  microphone entry for the whole window, and the launched `Lulo` has zero
  windows. Nobody at the machine could have clicked anything.
- `AVCaptureDevice.authorizationStatus(for: .audio)` returns **authorized**,
  and the built host carries both `com.apple.security.device.audio-input` and
  `NSMicrophoneUsageDescription`. Permission is not what is missing.
- The same experiment as a standalone `swift` script, outside XCTest
  entirely, also hangs — killed at **600s** with no output. So this is not
  something `xcodebuild` is doing.
- Enumerating the devices returns instantly: four inputs, none
  `isInUseByAnotherApplication`, the built-in microphone is the default and
  is free.

**The second** — written a few hours later, from the evidence just above —
concluded that a wedged virtual HAL driver was hanging every process that
touched CoreAudio, that the machine owner would have to disable
`iShotAudioPlugin` / `MSLoopbackDriverDevice` / 「Yii麥克風」 to find out, and
that "the answer cannot be got from an agent-spawned process on this
machine." Every one of those is wrong. The answer was got from an
agent-spawned process, with all four HAL plugins still installed —
`KrispAudio`, `MSTeamsAudioDevice`, `ParrotAudioPlugin`, `iShotAudioPlugin`
— and nothing disabled.

**What actually happened is that the machine was restarted.** It booted at
19:02 and `coreaudiod` came up at 19:06; every hang recorded above is from
before that, and every run that works is from after. CoreAudio was wedged,
and a wedged CoreAudio hangs the input graph without touching permissions,
without logging to `tccd`, and without making the devices look busy — which
is exactly the evidence above, and exactly why it read as something
structural.

**The lesson is about the shape of the reasoning, not about audio.** Both
wrong explanations were built by ruling things out — not a prompt, not
permission, not a busy device, not `xcodebuild` — and then handing the
remainder to the most complicated suspect still standing. Elimination cannot
reach a cause that is not on the list, and "the daemon is wedged and a
restart clears it" was never on it. When every specific suspect has been
cleared and the conclusion is getting more elaborate, the next move is to
re-run the cheap experiment in a fresh environment before writing anything
down. That costs a minute; the second explanation cost a day of somebody
else's plan and told them to uninstall their audio software.

The bounded experiment is also part of the lesson. The runs that produced
the wrong conclusion were killed at 19, 7 and 4 minutes, and the standalone
one at 600 seconds. The run that produced the right one was capped at 60
seconds and printed a line before and after every call, so "it hung" could
have named the call it hung in. It finished in two.

If both engines run, the rest is mechanical and every piece already exists:

1. **The key.** A second `GlobalHotKeyController` already works — its id
   collision with ⌘⇧Space was found and fixed while the reverted version was
   being built, and `testTwoControllersNeverMintTheSameIdentifier` pins it.
   Not ⌘⇧D: Finder, Mail and most editors use it, and a Carbon hot key beats
   the frontmost app's menu.
2. **Its own engine, started on press and stopped on release.** Not the
   conversation's session, and never touching `mute`, `VoiceActivityBox`,
   `TurnCompletion` or `heldSpeech` — those are the four things that broke.
   The conversation does not need to know a dictation is happening, which is
   the entire point.
3. **Its own `HeldSpeechCaptureBox`.** Note that `begin()` deliberately
   resets unconditionally so push-to-talk can recover from a release Carbon
   never delivered; a dictation key with no hold splitter needs its own
   key-repeat guard at the call site rather than changing that.
4. **`transcribeHeld`**, which already takes a timeout and already
   distinguishes "no recogniser" from "heard nothing".
5. **`NSPasteboard`**, which needs no entitlement to write.
6. **The outcome shape**, which was written and reviewed before the revert:
   copied / heard nothing / microphone closed / recogniser unreachable, four
   states because they send the user to do four different things, and a
   menu-bar signal because the user is by definition looking at another app.

The first word is the known cost and is still unmeasured: an engine started
on the keypress is not yet running when the first syllable arrives. Measure
it before deciding whether the engine should idle warm.

## What was kept

Three fixes that stand on their own and are unrelated to dictation:

- **`GlobalHotKeyController.nextID` is now `static`.** It was per-instance,
  and Carbon addresses a registration by `(signature, id)` with one shared
  signature — so a second controller minted id 1 again and its handler
  answered for the first controller's key. Latent until something registered
  a second hotkey; adding dictation is what exposed it. Pinned by
  `testTwoControllersNeverMintTheSameIdentifier`.
- **`sweepHeldClips`** deletes held-speech WAVs older than an hour. These
  are recordings of somebody's voice, written to be re-listened to while
  recognisers were compared, and nothing ever removed them.
- **`transcribeHeld` returns `String?`**, where nil is "could not reach the
  recogniser" and empty is "heard nothing". The conversation still treats
  them alike — the streamed transcript stands either way — but they are
  different things to tell anyone who asks, and collapsing them at the
  boundary loses that for good.

## The wider problem this sits on

Both sidecars — TTS on 46557 and the batch recogniser on 46558 — live
outside this repository, are started by hand, and fail silently. The app
sandbox cannot spawn a subprocess, so launching them from Lulo is closed
off. Nothing in the app tells the user when either is down; the voice simply
does not speak and the batch transcript simply does not arrive. Any feature
that depends on a sidecar inherits that, and dictation would have inherited
it worst, since it has nothing to fall back on. Worth fixing before the next
attempt, and not fixed here.
