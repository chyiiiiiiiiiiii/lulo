#!/usr/bin/env python3
"""Tests for measuring one rendered probe.

Synthetic two-syllable words with tones built into them by construction, so
the expected answer is known without anyone having to listen.
"""

from __future__ import annotations

import unittest

import numpy as np

from measure import measure_probe
from tone import TONE_FALLING, TONE_HIGH, TONE_RISING

RATE = 24000
BASE = 130.0


def syllable(start_semitones: float, end_semitones: float, seconds: float = 0.28):
    """A voiced syllable whose pitch glides between two semitone offsets."""
    n = int(RATE * seconds)
    start = BASE * 2 ** (start_semitones / 12)
    end = BASE * 2 ** (end_semitones / 12)
    frequency = np.linspace(start, end, n)
    phase = np.cumsum(frequency) / RATE
    envelope = np.ones(n)
    # Fade the edges, so the cut between syllables lands in a dip the way
    # it does in speech rather than on a discontinuity.
    fade = max(1, n // 10)
    envelope[:fade] = np.linspace(0.05, 1.0, fade)
    envelope[-fade:] = np.linspace(1.0, 0.05, fade)
    return (2.0 * (phase % 1.0) - 1.0) * 0.3 * envelope


def gap(seconds: float = 0.06):
    return np.zeros(int(RATE * seconds))


class MeasureProbeTest(unittest.TestCase):
    def test_it_measures_the_syllable_it_was_asked_about(self) -> None:
        # First syllable falls, second is level. Asking about each in turn
        # must give different answers, or the index is being ignored and
        # every probe is really measuring the same thing.
        word = np.concatenate([syllable(6, -6), gap(), syllable(5, 5)])

        first = measure_probe(word, RATE, "p", 2, 0, TONE_FALLING)
        second = measure_probe(word, RATE, "p", 2, 1, TONE_HIGH)

        self.assertEqual(first.measured_tone, TONE_FALLING)
        self.assertEqual(second.measured_tone, TONE_HIGH)
        self.assertTrue(first.correct)
        self.assertTrue(second.correct)

    def test_a_wrong_tone_is_reported_as_wrong_not_as_a_failure(self) -> None:
        word = np.concatenate([syllable(-3, 4), gap(), syllable(5, 5)])
        measured = measure_probe(word, RATE, "p", 2, 0, TONE_FALLING)
        self.assertEqual(measured.measured_tone, TONE_RISING)
        self.assertFalse(measured.correct)
        self.assertIsNone(measured.failure)

    def test_the_reference_comes_from_the_whole_word(self) -> None:
        # Taken per syllable, every syllable would centre on itself and
        # every tone would read as level. A falling syllable that stays
        # above the word's median must still read as falling.
        word = np.concatenate([syllable(8, 1), gap(), syllable(-6, -6)])
        measured = measure_probe(word, RATE, "p", 2, 0, TONE_FALLING)
        self.assertEqual(measured.measured_tone, TONE_FALLING)

    def test_silence_is_a_failed_measurement_not_a_bad_voice(self) -> None:
        measured = measure_probe(np.zeros(RATE // 2), RATE, "p", 2, 0, TONE_HIGH)
        self.assertIsNone(measured.measured_tone)
        self.assertFalse(measured.correct)
        self.assertIsNotNone(measured.failure)

    def test_a_render_that_lost_a_syllable_is_a_failed_measurement(self) -> None:
        # One syllable where the probe expects two means the render is not
        # what was asked for. Scoring its pitch would be scoring the wrong
        # word.
        word = syllable(5, 5, seconds=0.3)
        measured = measure_probe(word, RATE, "p", 2, 1, TONE_HIGH)
        self.assertIsNone(measured.measured_tone)
        self.assertIn("syllable", measured.failure or "")

    def test_asking_past_the_end_of_the_word_is_refused(self) -> None:
        word = np.concatenate([syllable(5, 5), gap(), syllable(5, 5)])
        measured = measure_probe(word, RATE, "p", 2, 5, TONE_HIGH)
        self.assertIsNone(measured.measured_tone)
        self.assertIsNotNone(measured.failure)

    def test_the_duration_is_reported_even_when_nothing_could_be_read(self) -> None:
        # A render that came back far too short is the most common way a
        # model fails, and the length is what makes that visible.
        measured = measure_probe(np.zeros(RATE // 10), RATE, "p", 2, 0, TONE_HIGH)
        self.assertAlmostEqual(measured.seconds, 0.1, places=3)


if __name__ == "__main__":
    unittest.main()
