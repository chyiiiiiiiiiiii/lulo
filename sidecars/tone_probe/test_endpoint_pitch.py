#!/usr/bin/env python3
"""The endpoint-pitch probe, on signals whose answer is known.

The corpus this probe was written for is private and gitignored, so nothing
here touches it. What is checked instead is that the instrument reports what
it is told to report — which is the half of the Smart Turn method that
mattered: the negative result was only believable because the instrument had
been shown to work first.
"""

from __future__ import annotations

import unittest

import numpy as np

from endpoint_pitch import (
    FRAME_MS,
    describe,
    frame_rms,
    pauses,
    speech_mask,
)


def tone(hz: float, seconds: float, rate: int = 16_000) -> np.ndarray:
    span = np.arange(int(rate * seconds), dtype=np.float64)
    return 0.4 * np.sin(2 * np.pi * hz * span / rate)


def silence(seconds: float, rate: int = 16_000) -> np.ndarray:
    return np.zeros(int(rate * seconds))


class SpeechMaskTests(unittest.TestCase):
    def test_a_gap_between_two_sounds_is_found(self) -> None:
        samples = np.concatenate(
            [tone(120, 0.5), silence(0.4), tone(120, 0.5)]
        )
        gaps, ended = pauses(speech_mask(frame_rms(samples, 16_000)))

        self.assertEqual(len(gaps), 1)
        start, stop = gaps[0]
        self.assertAlmostEqual((stop - start) * FRAME_MS, 400, delta=60)
        self.assertAlmostEqual(ended * FRAME_MS, 1400, delta=60)

    def test_a_gap_too_short_to_endpoint_on_is_not_reported(self) -> None:
        # Below 150ms nothing in the pipeline would have considered
        # endpointing, so reporting it would only add noise to the table.
        samples = np.concatenate(
            [tone(120, 0.5), silence(0.05), tone(120, 0.5)]
        )
        gaps, _ = pauses(speech_mask(frame_rms(samples, 16_000)))

        self.assertEqual(gaps, [])

    def test_unbroken_sound_has_no_pauses(self) -> None:
        gaps, ended = pauses(speech_mask(frame_rms(tone(120, 1.0), 16_000)))

        self.assertEqual(gaps, [])
        self.assertGreater(ended, 0)


class DescribeTests(unittest.TestCase):
    def test_a_pitch_at_the_bottom_of_the_range_reads_as_the_bottom(self) -> None:
        stats = describe([100.0] * 10, low=100.0, high=200.0)

        self.assertAlmostEqual(stats["position"], 0.0, places=2)

    def test_a_pitch_at_the_top_of_the_range_reads_as_the_top(self) -> None:
        stats = describe([200.0] * 10, low=100.0, high=200.0)

        self.assertAlmostEqual(stats["position"], 1.0, places=2)

    def test_a_falling_track_reports_a_negative_slope(self) -> None:
        stats = describe([200.0, 180.0, 160.0, 140.0, 120.0, 100.0], 100.0, 200.0)

        self.assertLess(stats["slope_st"], -8)

    def test_a_rising_track_reports_a_positive_slope(self) -> None:
        stats = describe([100.0, 120.0, 140.0, 160.0, 180.0, 200.0], 100.0, 200.0)

        self.assertGreater(stats["slope_st"], 8)

    def test_too_few_voiced_frames_report_nothing_rather_than_a_guess(self) -> None:
        self.assertEqual(describe([], 100.0, 200.0), {})
        self.assertEqual(describe([120.0], 100.0, 200.0), {})


if __name__ == "__main__":
    unittest.main()
