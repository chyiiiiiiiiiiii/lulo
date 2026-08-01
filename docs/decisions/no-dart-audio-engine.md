# Audio playback stays inside the voice-processed graph

**Status:** accepted
**Decided:** no commit — this record refuses a change rather than making one
**Depends on:** [full-duplex-voice.md](full-duplex-voice.md)

## The decision

The TTS sidecar's PCM is played by an `AVAudioPlayerNode` attached to the
same `AVAudioEngine` that carries the microphone
(`VoiceHostAdapter.swift:613`). **No Dart-side audio engine — `flutter_soloud`,
`just_audio`, `audioplayers` — goes into that path.** The app's audio
dependencies stay at zero, and the whole output route stays in Swift.

The question is asked about `flutter_soloud` specifically, because it is the
package a Flutter developer reaches for when a project needs sound. It is a
good package. It solves a problem this project does not have, and it would
undo the one it does.

## Why any Dart audio engine breaks full duplex

The echo canceller lives in a single Voice-Processing I/O unit that owns
**both** ends of the audio. It subtracts the agent's voice from the
microphone by holding the far end — what the speakers are playing — as a
reference. That is the entire reason the player node is on
`engine.mainMixerNode` rather than anywhere convenient.

`flutter_soloud` is backed by miniaudio and opens its own output device.
Audio played through it never enters the voice-processed graph, so the
canceller has no far-end reference and subtracts nothing.

That failure has already been measured here, twice, and it does not announce
itself as an audio bug:

```
partial (2 chars) peak 0.1443 floor 0.0021 WHILE SPEAKING
  "Fl" → yield speaking=true cancelsGeneration=TRUE
  "Flonter Google的這個技"
```

The transcriber hears the agent, one non-empty partial cancels the answer,
and a cancelled answer is never spoken — **the agent talks itself into
silence and stays there.** `full-duplex-voice.md` is the whole story;
the point for this record is that swapping the output engine reproduces it
exactly, from a change that looks like a dependency upgrade.

## What it offers against what the voice pipeline needs

| The pipeline needs | Where it comes from today | `flutter_soloud` |
|---|---|---|
| Acoustic echo cancellation | Apple VP I/O unit, both ends | — |
| Voice activity detection | `VoiceActivityBox`, RMS over an adaptive floor | — |
| Speech recognition | `SpeechAnalyzer` + `SpeechTranscriber` | — |
| Endpointing | `checkEndpoint`, two clocks and four guards | — |
| Play a float32 PCM stream | `AVAudioPlayerNode.scheduleBuffer` | ✓, on its own device |

Its feature list is 3D positional audio, reverb and echo filters, FFT for
visualisation, mixing buses, sample-accurate scheduling. Every one of those
is for games and media. The only capture it does is of its own master mixer
output — recording what it plays, not conditioning a microphone.

The single row it can fill is the one row already working.

## The sidecar's own speaker is not a target either

`POST /speak` plays through `sounddevice` in the Python process, outside
every graph. That is deliberate: `/speak` is the **half-duplex fallback**,
where the microphone is muted for the duration of the answer and there is
nothing for a canceller to do. Moving it into a Dart engine would add a
dependency to a path whose defining property is that it needs no help.

The ordinary path is `/render` → `renderAndPlay` → the player node, and that
one is already where it has to be.

## If this ever goes cross-platform

`AVAudioEngine` and `setVoiceProcessingEnabled` are Apple's, so iOS carries
over and Windows and Linux do not. That is a real reason to revisit the
output path — and `flutter_soloud` is still not the answer, because the
missing piece on those platforms is the canceller, not the player. What to
look at then is WebRTC's audio processing module or `speexdsp`: something
that does AEC, with playback arranged around whatever reference signal it
requires.

Reaching for a Dart playback package at that point would answer the easy half
of the problem and quietly delete the hard half. It is the same error the
first two full-duplex measurements made: fixing the near end and calling the
far end done.

## The trap in one line

**Anything that plays audio outside `VoiceHostAdapter`'s engine is a
regression to `f4309e9`, however good the package is.**
