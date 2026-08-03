#!/usr/bin/env python3
"""Measuring one rendered probe.

Joins the two halves: find the syllable the probe is about, read the pitch
across it, and say which tone that shape is. Kept separate from both so the
join can be tested without a model and without a microphone.
"""

from __future__ import annotations

import wave

import numpy as np

from pitch import syllable_spans, track_pitch
from tone import classify_tone, reference_pitch


class Measurement:
    """What one rendered probe turned out to be."""

    def __init__(
        self,
        probe_id: str,
        expected_tone: int,
        measured_tone: int | None,
        reference_hz: float | None,
        seconds: float,
        failure: str | None = None,
    ) -> None:
        self.probe_id = probe_id
        self.expected_tone = expected_tone
        self.measured_tone = measured_tone
        self.reference_hz = reference_hz
        self.seconds = seconds
        # Why nothing could be measured, when nothing could. Kept apart
        # from a wrong tone so a broken render never reads as a bad voice.
        self.failure = failure

    @property
    def correct(self) -> bool:
        return self.measured_tone is not None and self.measured_tone == self.expected_tone

    def as_dict(self) -> dict[str, object]:
        return {
            "id": self.probe_id,
            "expectedTone": self.expected_tone,
            "measuredTone": self.measured_tone,
            "correct": self.correct,
            "referenceHz": self.reference_hz,
            "seconds": self.seconds,
            "failure": self.failure,
        }


def read_wav(path: str) -> tuple[np.ndarray, int]:
    """Mono float samples and the sample rate of the WAV at [path]."""
    with wave.open(path, "rb") as handle:
        rate = handle.getframerate()
        channels = handle.getnchannels()
        width = handle.getsampwidth()
        frames = handle.readframes(handle.getnframes())
    if width != 2:
        raise ValueError(f"{path} is not 16-bit; got {width * 8}-bit.")
    samples = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0
    if channels > 1:
        samples = samples.reshape(-1, channels).mean(axis=1)
    return samples, rate


def measure_probe(
    samples: np.ndarray,
    rate: int,
    probe_id: str,
    syllable_count: int,
    syllable_index: int,
    expected_tone: int,
) -> Measurement:
    """Which tone the rendered audio actually carries on the syllable tested.

    The reference pitch comes from the whole word rather than the syllable
    under test. A tone is a shape against the speaker's range, and taking
    the reference from the syllable itself would normalise away exactly
    what is being measured -- every syllable would sit at zero and every
    tone would read as level.
    """
    seconds = samples.size / rate if rate else 0.0
    if syllable_index >= syllable_count:
        return Measurement(
            probe_id, expected_tone, None, None, seconds,
            failure="the syllable tested is not in the word",
        )

    whole = track_pitch(samples, rate)
    reference = reference_pitch(whole)
    if reference is None:
        return Measurement(
            probe_id, expected_tone, None, None, seconds,
            failure="nothing voiced in the render",
        )

    spans = syllable_spans(samples, rate, syllable_count)
    if len(spans) != syllable_count:
        return Measurement(
            probe_id, expected_tone, None, reference, seconds,
            failure=f"found {len(spans)} syllables, expected {syllable_count}",
        )

    start, end = spans[syllable_index]
    contour = track_pitch(samples[start:end], rate)
    measured = classify_tone(contour, reference)
    failure = None if measured is not None else "the contour had no readable shape"
    return Measurement(
        probe_id, expected_tone, measured, reference, seconds, failure=failure
    )
