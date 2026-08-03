#!/usr/bin/env python3
"""Tests for the pitch tracker and the syllable splitter.

Synthetic audio throughout, because these tests have to be able to fail.
Real speech has no ground truth on this machine: nobody has labelled the
pitch of the corpus frame by frame, so a test against it could only assert
that the tracker agrees with itself. A sawtooth at a known frequency has a
right answer, and a tracker that locks on to a harmonic gets it wrong.
"""

from __future__ import annotations

import unittest

import numpy as np

from pitch import syllable_spans, track_pitch

RATE = 24000


def voiced(frequency: float, seconds: float, rate: int = RATE) -> np.ndarray:
    """A sawtooth at [frequency].

    Sawtooth rather than a sine: it carries the harmonic stack that real
    voicing has, which is what makes octave errors possible in the first
    place. A tracker tested only on sine waves would never meet the
    failure it is most likely to have.
    """
    t = np.arange(int(rate * seconds)) / rate
    phase = (t * frequency) % 1.0
    return (2.0 * phase - 1.0) * 0.3


def unvoiced(seconds: float, rate: int = RATE) -> np.ndarray:
    """Noise, at the level of a fricative."""
    generator = np.random.default_rng(7)
    return generator.normal(0.0, 0.05, int(rate * seconds))


def silence(seconds: float, rate: int = RATE) -> np.ndarray:
    return np.zeros(int(rate * seconds))


def glide(start: float, end: float, seconds: float, rate: int = RATE) -> np.ndarray:
    """A sawtooth sweeping from [start] to [end] hertz, as a tone does."""
    n = int(rate * seconds)
    frequency = np.linspace(start, end, n)
    phase = np.cumsum(frequency) / rate
    return (2.0 * (phase % 1.0) - 1.0) * 0.3


class TrackPitchTest(unittest.TestCase):
    def test_a_steady_note_reads_back_as_itself(self) -> None:
        track = [value for value in track_pitch(voiced(150.0, 0.5), RATE) if value > 0]
        self.assertGreater(len(track), 10)
        measured = float(np.median(track))
        self.assertAlmostEqual(measured, 150.0, delta=3.0)

    def test_a_low_voice_and_a_high_one_are_both_found(self) -> None:
        # The window has to hold two periods of the lowest pitch and still
        # resolve the highest. Both ends of the range are checked because
        # only one of them is a frame-length problem.
        for frequency in (80.0, 320.0):
            track = [v for v in track_pitch(voiced(frequency, 0.4), RATE) if v > 0]
            self.assertGreater(len(track), 5, f"{frequency} Hz found nothing")
            self.assertAlmostEqual(
                float(np.median(track)), frequency, delta=frequency * 0.04
            )

    def test_a_rising_note_is_measured_rising(self) -> None:
        # The property the tone classifier depends on. A tracker that
        # returned a flat median for a glide would make every second tone
        # look like a first.
        track = [v for v in track_pitch(glide(110.0, 190.0, 0.5), RATE) if v > 0]
        self.assertGreater(len(track), 10)
        third = len(track) // 3
        self.assertLess(float(np.median(track[:third])), 130.0)
        self.assertGreater(float(np.median(track[-third:])), 165.0)

    def test_noise_is_not_reported_as_a_pitch(self) -> None:
        # A fricative has no period. Calling it voiced feeds the classifier
        # a contour that came from nothing.
        track = track_pitch(unvoiced(0.4), RATE)
        voiced_frames = [value for value in track if value > 0]
        self.assertLess(len(voiced_frames), max(1, len(track) // 4))

    def test_silence_is_unvoiced_throughout(self) -> None:
        self.assertEqual([v for v in track_pitch(silence(0.3), RATE) if v > 0], [])

    def test_audio_shorter_than_one_frame_has_no_track(self) -> None:
        self.assertEqual(track_pitch(voiced(150.0, 0.005), RATE), [])

    def test_a_sample_rate_of_zero_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            track_pitch(voiced(150.0, 0.2), 0)


class SyllableSpansTest(unittest.TestCase):
    def test_two_syllables_separated_by_a_closure(self) -> None:
        audio = np.concatenate(
            [silence(0.05), voiced(150.0, 0.25), silence(0.08),
             voiced(180.0, 0.25), silence(0.05)]
        )
        spans = syllable_spans(audio, RATE, 2)
        self.assertEqual(len(spans), 2)
        first, second = spans
        self.assertLess(first[1], second[0] + RATE * 0.05)
        # Each span should hold most of its own syllable.
        self.assertGreater(first[1] - first[0], RATE * 0.15)
        self.assertGreater(second[1] - second[0], RATE * 0.15)

    def test_syllables_that_run_together_are_still_split(self) -> None:
        # Mandarin does not leave gaps. The dip of an unvoiced initial is
        # all there is to cut on, and waiting for silence would find one
        # syllable where there are two.
        audio = np.concatenate(
            [voiced(150.0, 0.22), unvoiced(0.06), voiced(190.0, 0.22)]
        )
        spans = syllable_spans(audio, RATE, 2)
        self.assertEqual(len(spans), 2)
        boundary = spans[0][1]
        self.assertGreater(boundary, RATE * 0.15)
        self.assertLess(boundary, RATE * 0.36)

    def test_three_syllables_split_three_ways(self) -> None:
        audio = np.concatenate(
            [voiced(150.0, 0.2), silence(0.06), voiced(170.0, 0.2),
             silence(0.06), voiced(190.0, 0.2)]
        )
        spans = syllable_spans(audio, RATE, 3)
        self.assertEqual(len(spans), 3)
        self.assertTrue(all(end > start for start, end in spans))
        # In order and not overlapping, or the syllable under test is not
        # the one that gets measured.
        for earlier, later in zip(spans, spans[1:]):
            self.assertLessEqual(earlier[1], later[0] + 1)

    def test_one_syllable_is_the_whole_word(self) -> None:
        audio = np.concatenate([silence(0.05), voiced(150.0, 0.3), silence(0.05)])
        spans = syllable_spans(audio, RATE, 1)
        self.assertEqual(len(spans), 1)
        self.assertGreater(spans[0][1] - spans[0][0], RATE * 0.25)

    def test_audio_too_short_to_hold_the_syllables_returns_nothing(self) -> None:
        # Reported as no measurement rather than as crowded spans, so a
        # failed render cannot be scored as a mispronunciation.
        self.assertEqual(syllable_spans(voiced(150.0, 0.01), RATE, 3), [])

    def test_silence_has_no_syllables(self) -> None:
        self.assertEqual(syllable_spans(silence(0.5), RATE, 2), [])

    def test_a_word_with_no_syllables_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            syllable_spans(voiced(150.0, 0.3), RATE, 0)


if __name__ == "__main__":
    unittest.main()
