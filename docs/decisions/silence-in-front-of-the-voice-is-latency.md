# The silence in front of the voice is latency, and 0.4s chunks are safe

**Status:** measured and shipped
**Decided:** `lulo-tts` `ba88e99` (the trim) and `09aac0d` (the interval)
**Depends on:** [voice-turn-latency.md](voice-turn-latency.md) — this closes
the last segment that record left open, the one between the sidecar being
asked and a sound existing

## The decision

Two things sat in front of Lulo's voice that were pure waiting, and both are
gone:

1. **The model's leading silence is trimmed.** Qwen3-TTS returns the
   utterance's leading silence inside its first chunk — measured 0.21s to
   0.93s of digital zeros on the ryan clone. `onset.py` finds the onset and
   drops everything before it, in both the `/speak` and `/render` paths.
2. **`STREAM_INTERVAL` is 0.4, not 0.8.** The first chunk cannot be heard
   until it exists, so the interval is the floor under time-to-first-audio:
   0.62s at 0.8, 0.33s at 0.4.

Measured end to end on five sentences, audible time-to-first-audio is now
**0.30s to 0.71s**, from roughly double that.

**Do not raise either number back without reading the rest of this file.**
Both were defended by reasoning that was true when it was written.

## Why the trim is safe, and where it stops

Silence is dropped *only in front of the utterance*. Once the voice has been
heard the trimmer stands down and every later chunk passes through
untouched, because a pause in the middle of a sentence is prosody and
prosody is not latency. The threshold is -50 dBFS over 10ms windows, sound
must hold 30ms to count as speech rather than a click, 20ms of pre-roll
survives so the attack is not clipped, and past 2s of dropped audio it gives
up rather than behead a malformed utterance. `test_onset.py` holds each of
those.

The threshold is 0.003 rather than 0.01 because the tighter one cut 200ms
deeper into 你好 — into the breath before the 你, which is audible when it
is missing.

## Why 0.4 is not the babble it was recorded as

`STREAM_INTERVAL` carried a comment, and this document's predecessor carried
the same claim: *0.4s intervals occasionally sent one benchmark sentence
into a babble loop; 0.8 stayed stable.* That was a real observation. It was
not a real cause.

The reading is from `lulo-tts` `3adce68`, dated the day before `631d9f7`
made the voice a cloned recording decoded at `top_k` 1. Before that commit
every render was a fresh sample of the acoustics — the same commit message
calls the old behaviour a dice roll — so a sentence could babble on any
setting, and the interval was simply what was being turned when one did.

Structurally the chunk size cannot reach the talker at all.
`streaming_chunk_size` only gates *when* the codec decodes codes that have
already been generated; the decoder's output never feeds back into the
generation loop. Measured across intervals 0.8 / 0.4 / 0.24 / 0.08 on the
same sentence: identical token count, identical audio length to the sample,
and identical transcripts back through Breeze ASR. The waveforms differ only
by a diffuse ~-26 dB numeric difference from decoding in different-sized
pieces — spread evenly through the utterance rather than sitting on the
chunk boundaries, which is what an actual seam would look like.

## Why it stops at 0.4 and does not go lower

Below 0.4 the latency stops being free:

| `streaming_interval` | first chunk | RTF | worst gap between chunks |
|---|---|---|---|
| 0.8 | 0.62s | 0.64 | 0.734s |
| **0.4** | **0.33s** | **0.62** | 0.334s |
| 0.24 | 0.24s | 0.76 | 0.396s |
| 0.16 | 0.22s | 0.79 | 0.253s |

At 0.4 the throughput is unchanged and each gap between chunks is still
shorter than the audio the chunk before it carried, which is the condition
for playback never running dry. At 0.24 the decoder is called often enough
to cost 18% of the generation budget, and the worst gap (0.396s) is longer
than the 0.24s of audio it delivers — the buffer starts draining, and
`PLAYER_MIN_BUFFER_S` is the only thing left absorbing it.

## What was considered and not done

**Ramping the chunk size** — small first chunk, larger later ones — is what
[Nari Labs' Qwen3-TTS serving write-up](https://nari-labs.com/blog/qwen3-tts-speed-cost-frontier/)
does, and it is where this investigation started. It was dropped: their
reason for ramping is batching efficiency across concurrent requests, and
this sidecar serves one utterance at a time. A flat 0.4 collects the whole
win. It would also have needed patching the model — `streaming_chunk_size`
is computed once as a local inside `_generate_icl`, so nothing outside can
vary it mid-generation.

**Rebuilding the codec around cached state**, the same write-up's other
transferable idea, turned out to be already done upstream: mlx-audio's
`streaming_step()` keeps conv buffers, a transformer KV cache, and
overlap-add state for the transposed convolutions, and decodes only new
tokens. Nothing to do.
