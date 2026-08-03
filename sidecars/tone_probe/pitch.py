#!/usr/bin/env python3
"""Finding the pitch, and finding where each syllable starts and stops.

Autocorrelation rather than a library. Not for purity: librosa pulls in
numba and this machine has fifteen gigabytes left, and the measurement here
is narrow enough that the general tool would be doing the same thing with
more machinery. Speech at a known sample rate, one speaker, a pitch that
stays inside a two-octave window — the peak of the normalised
autocorrelation is the period, and there is nothing else to decide.

Syllables are found by energy rather than by recognising anything. A probe
is one word of two or three syllables rendered on its own, so the valleys
between them are the quietest points in the recording. That does not
generalise to running speech, which is why probes are single words.
"""

from __future__ import annotations

import numpy as np

# A human speaking pitch, generously bounded. Below 60 Hz is a room, above
# 400 Hz is either a child or the tracker locking on to a harmonic.
MIN_PITCH_HZ = 60.0
MAX_PITCH_HZ = 400.0

# How confident the autocorrelation peak has to be before a frame counts as
# voiced. Aperiodic sound -- a fricative, a room -- has no peak worth the
# name, and calling it voiced would feed the tone classifier noise shaped
# like a contour.
_VOICING_THRESHOLD = 0.35


def track_pitch(
    samples: np.ndarray,
    rate: int,
    frame_ms: float = 40.0,
    hop_ms: float = 10.0,
) -> list[float]:
    """The pitch of [samples], one value per hop, zero where unvoiced.

    A 40 ms frame holds at least two periods of the lowest pitch this looks
    for, which is what autocorrelation needs to see a period at all.
    """
    if rate <= 0:
        raise ValueError("A pitch track needs a positive sample rate.")
    frame = int(rate * frame_ms / 1000.0)
    hop = int(rate * hop_ms / 1000.0)
    if frame <= 0 or hop <= 0 or samples.size < frame:
        return []

    min_lag = max(1, int(rate / MAX_PITCH_HZ))
    max_lag = min(frame - 1, int(rate / MIN_PITCH_HZ))
    if max_lag <= min_lag:
        return []

    track: list[float] = []
    for start in range(0, samples.size - frame + 1, hop):
        window = samples[start : start + frame].astype(np.float64)
        window = window - window.mean()
        energy = float(np.dot(window, window))
        if energy <= 1e-9:
            track.append(0.0)
            continue
        # Normalised by the zero-lag term, so the peak is a correlation
        # coefficient and the threshold above means the same thing whether
        # the speaker is loud or quiet.
        correlation = np.correlate(window, window, mode="full")[frame - 1 :]
        correlation = correlation / energy
        segment = correlation[min_lag : max_lag + 1]
        if segment.size == 0:
            track.append(0.0)
            continue
        peak = int(np.argmax(segment))
        if float(segment[peak]) < _VOICING_THRESHOLD:
            track.append(0.0)
            continue
        track.append(rate / float(peak + min_lag))
    return track


def _energy_envelope(samples: np.ndarray, rate: int, hop_ms: float) -> np.ndarray:
    """Short-time energy, one value per hop, smoothed."""
    hop = max(1, int(rate * hop_ms / 1000.0))
    frames = samples.size // hop
    if frames == 0:
        return np.zeros(0)
    trimmed = samples[: frames * hop].reshape(frames, hop)
    energy = np.sqrt((trimmed.astype(np.float64) ** 2).mean(axis=1))
    # A three-frame box, so one clipped sample cannot look like a syllable
    # boundary while a real 30 ms closure still does.
    if energy.size >= 3:
        energy = np.convolve(energy, np.ones(3) / 3.0, mode="same")
    return energy


# How far a candidate boundary has to fall below the quieter of the two
# peaks around it before it counts as a boundary at all.
#
# Without this, every recording has boundaries: the quietest interior frame
# of one continuous syllable is still the quietest interior frame, so a
# render that dropped a syllable was cut in half and measured as though it
# had not. That is the worst failure this file can have, because it does
# not look like a failure -- it produces a tone, and the tone is scored.
_VALLEY_DEPTH = 0.35


def _is_valley(
    envelope: np.ndarray,
    index: int,
    first: int,
    last: int,
) -> bool:
    """Whether [index] is a real dip rather than the flattest point of a slope."""
    left = envelope[first : index + 1]
    right = envelope[index : last + 1]
    if left.size == 0 or right.size == 0:
        return False
    shoulder = min(float(left.max()), float(right.max()))
    if shoulder <= 0:
        return False
    return float(envelope[index]) <= shoulder * (1.0 - _VALLEY_DEPTH)


def syllable_spans(
    samples: np.ndarray,
    rate: int,
    count: int,
    hop_ms: float = 10.0,
) -> list[tuple[int, int]]:
    """[count] syllable spans in [samples], as sample indices.

    Cuts at the quietest interior points rather than at silence: Mandarin
    syllables run together and an unvoiced initial makes a dip, not a gap,
    so waiting for silence would find one syllable where there are two.

    Returns fewer spans than asked for only when the audio is too short to
    hold them, which the caller must treat as a failed measurement rather
    than as a result.
    """
    if count < 1:
        raise ValueError("A word has at least one syllable.")
    envelope = _energy_envelope(samples, rate, hop_ms)
    if envelope.size == 0:
        return []
    hop = max(1, int(rate * hop_ms / 1000.0))

    # The spoken part, trimmed of leading and trailing quiet so the cuts
    # divide speech rather than the silence around it.
    speaking = np.where(envelope > envelope.max() * 0.1)[0]
    if speaking.size == 0:
        return []
    first, last = int(speaking[0]), int(speaking[-1])
    if count == 1:
        return [(first * hop, min((last + 1) * hop, samples.size))]

    # Interior minima, taken one at a time and forbidden from landing next
    # to a cut already made: the quietest two frames in a recording are
    # usually adjacent, and cutting at both would produce an empty syllable
    # and swallow a real one.
    span = last - first
    if span < count * 2:
        return []
    guard = max(1, span // (count * 3))
    cuts: list[int] = []
    candidates = sorted(range(first + guard, last - guard), key=lambda i: envelope[i])
    for index in candidates:
        if len(cuts) == count - 1:
            break
        if any(abs(index - cut) <= guard for cut in cuts):
            continue
        if not _is_valley(envelope, index, first, last):
            continue
        cuts.append(index)
    if len(cuts) < count - 1:
        return []

    edges = [first, *sorted(cuts), last + 1]
    return [
        (edges[i] * hop, min(edges[i + 1] * hop, samples.size))
        for i in range(count)
    ]
