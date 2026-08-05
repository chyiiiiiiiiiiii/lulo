#!/usr/bin/env python3
"""Does the pitch before a pause say whether the speaker has finished?

Lives in this package because this is where the pitch tracker is, not
because it is about the voice: the question here is about the endpointer.

The question this answers is narrow and already has a benchmark. Over the
same twelve recordings, `docs/decisions/voice-turn-latency.md` found that
silence alone cannot separate a thinking pause from the end of a turn (the
distributions overlap: mid-utterance pauses reach 1.02s against an 0.8s
threshold), and that Smart Turn v3.2 could not either (0.973-0.988 against
0.978-0.989, saturated).

Final lowering -- the pitch falling to the bottom of the speaker's range at
the end of an utterance -- is one of the best-attested near-universal
turn-end cues. If it separates these two populations here, it is a
language-independent replacement for half the lexicon. If it does not, that
is worth twenty minutes to learn.

Answered, and the answer is no. See
`docs/decisions/turn-taking-by-words.md`.

Run: python3 endpoint_pitch.py <corpus-audio-dir> <corpus.json>

Caveat worth carrying: the pause detection below is an energy threshold, not
`VoiceActivityBox`'s minimum-statistics floor, so individual pause
boundaries move by a frame or two against production. The conclusion does
not rest on them — the two populations overlap on every metric, and a
boundary error would have to favour one population systematically to
manufacture that.
"""

from __future__ import annotations

import json
import math
import sys
import wave

import numpy as np

from pitch import track_pitch

FRAME_MS = 10.0
# A pause has to be this long to be worth asking about: below it, nothing in
# the pipeline would have considered endpointing anyway.
MIN_PAUSE_MS = 150.0
# How much speech before the pause the pitch is read from.
LOOKBACK_MS = 300.0


def read_wav(path: str) -> tuple[np.ndarray, int]:
    with wave.open(path, "rb") as handle:
        rate = handle.getframerate()
        channels = handle.getnchannels()
        width = handle.getsampwidth()
        raw = handle.readframes(handle.getnframes())
    if width != 2:
        raise ValueError(f"{path}: expected 16-bit PCM, got {width * 8}-bit")
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0
    if channels > 1:
        samples = samples.reshape(-1, channels).mean(axis=1)
    return samples, rate


def frame_rms(samples: np.ndarray, rate: int) -> np.ndarray:
    hop = max(1, int(rate * FRAME_MS / 1000.0))
    usable = (samples.size // hop) * hop
    if usable == 0:
        return np.zeros(0)
    blocks = samples[:usable].reshape(-1, hop)
    return np.sqrt((blocks * blocks).mean(axis=1))


def speech_mask(rms: np.ndarray) -> np.ndarray:
    """Which frames are speech, over an adaptive floor.

    The floor is the 10th percentile of the recording: read speech always
    has dips, and a room never does, so the quietest tenth is the room.
    """
    floor = float(np.percentile(rms, 10))
    peak = float(np.percentile(rms, 95))
    if peak <= floor:
        return np.zeros(rms.size, dtype=bool)
    threshold = floor + 0.10 * (peak - floor)
    return rms > threshold


def pauses(mask: np.ndarray) -> tuple[list[tuple[int, int]], int]:
    """Gaps inside speech, and the frame the last speech ended at."""
    voiced = np.flatnonzero(mask)
    if voiced.size == 0:
        return [], 0
    first, last = int(voiced[0]), int(voiced[-1])
    gaps: list[tuple[int, int]] = []
    run_start: int | None = None
    for index in range(first, last + 1):
        if not mask[index]:
            if run_start is None:
                run_start = index
        elif run_start is not None:
            if (index - run_start) * FRAME_MS >= MIN_PAUSE_MS:
                gaps.append((run_start, index))
            run_start = None
    return gaps, last + 1


def pitch_before(samples: np.ndarray, rate: int, end_frame: int) -> list[float]:
    end = int(end_frame * rate * FRAME_MS / 1000.0)
    start = max(0, end - int(rate * LOOKBACK_MS / 1000.0))
    if end - start < int(rate * 0.05):
        return []
    return [hz for hz in track_pitch(samples[start:end], rate) if hz > 0]


def semitones(hz: float, reference: float) -> float:
    return 12.0 * math.log2(hz / reference) if hz > 0 and reference > 0 else 0.0


def describe(track: list[float], low: float, high: float) -> dict[str, float]:
    """Where the pitch ended up, and which way it was going."""
    if len(track) < 3:
        return {}
    tail = track[-6:]  # the last ~60ms of voiced frames
    final = float(np.median(tail))
    # Where in the speaker's own range the final pitch sits: 0 is the bottom
    # of their voice, 1 the top. Normalised per speaker so the number means
    # the same thing for anybody.
    position = (final - low) / (high - low) if high > low else 0.5
    # Which way it was moving, in semitones across the read window.
    span = np.arange(len(track), dtype=np.float64)
    slope = float(np.polyfit(span, np.array(track, dtype=np.float64), 1)[0])
    return {
        "final_hz": final,
        "position": float(np.clip(position, 0.0, 1.0)),
        "slope_st": semitones(track[-1], track[0]) if track[0] > 0 else 0.0,
        "slope_hz_per_frame": slope,
    }


def main() -> int:
    audio_dir, manifest_path = sys.argv[1], sys.argv[2]
    manifest = json.load(open(manifest_path))
    rows: list[dict[str, object]] = []
    for case in manifest["cases"]:
        path = f"{audio_dir}/{case['id']}.wav"
        try:
            samples, rate = read_wav(path)
        except FileNotFoundError:
            print(f"missing: {path}")
            continue
        rms = frame_rms(samples, rate)
        mask = speech_mask(rms)
        gaps, ended = pauses(mask)
        whole = [hz for hz in track_pitch(samples, rate) if hz > 0]
        if len(whole) < 20:
            print(f"{case['id']}: too little voiced audio to measure")
            continue
        low = float(np.percentile(whole, 5))
        high = float(np.percentile(whole, 95))
        for start, stop in gaps:
            stats = describe(pitch_before(samples, rate, start), low, high)
            if stats:
                rows.append(
                    {
                        "case": case["id"],
                        "kind": "mid-pause",
                        "pause_ms": (stop - start) * FRAME_MS,
                        **stats,
                    }
                )
        stats = describe(pitch_before(samples, rate, ended), low, high)
        if stats:
            rows.append({"case": case["id"], "kind": "turn-end", "pause_ms": 0.0, **stats})

    header = f"{'case':<28}{'kind':<11}{'pause':>7}{'pos':>7}{'slope st':>10}{'final Hz':>10}"
    print(header)
    print("-" * len(header))
    for row in sorted(rows, key=lambda r: (r["kind"], r["position"])):
        print(
            f"{row['case']:<28}{row['kind']:<11}{row['pause_ms']:>6.0f}m"
            f"{row['position']:>7.2f}{row['slope_st']:>10.1f}{row['final_hz']:>10.0f}"
        )

    for kind in ("turn-end", "mid-pause"):
        group = [r for r in rows if r["kind"] == kind]
        if not group:
            continue
        pos = [r["position"] for r in group]
        slope = [r["slope_st"] for r in group]
        print(
            f"\n{kind}: n={len(group)} "
            f"position {min(pos):.2f}-{max(pos):.2f} (median {np.median(pos):.2f}) "
            f"slope {min(slope):+.1f}..{max(slope):+.1f} st "
            f"(median {np.median(slope):+.1f})"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
