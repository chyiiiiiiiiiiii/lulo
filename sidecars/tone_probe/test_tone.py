#!/usr/bin/env python3
"""Tests for reading a tone off a pitch contour."""

from __future__ import annotations

import math
import unittest

from probes import all_probes, probes_by_category
from tone import (
    TONE_DIPPING,
    TONE_FALLING,
    TONE_HIGH,
    TONE_RISING,
    classify_tone,
    reference_pitch,
    semitones,
    tone_accuracy,
    voiced_contour,
)

# A speaker's own pitch. Every contour below is built around it, so the
# tests exercise the same relative-to-speaker reasoning the real
# measurement does.
REFERENCE = 120.0


def contour(semitone_points: list[float], frames: int = 24) -> list[float]:
    """A pitch track in hertz through [semitone_points], relative to REFERENCE.

    Built from semitones rather than hertz so the shapes read as the tone
    descriptions they are meant to be: 55, 35, 214, 51.
    """
    if len(semitone_points) < 2:
        raise ValueError("A contour needs at least two points.")
    track: list[float] = []
    segments = len(semitone_points) - 1
    for index in range(frames):
        position = index / (frames - 1) * segments
        left = min(int(position), segments - 1)
        fraction = position - left
        value = (
            semitone_points[left] * (1 - fraction)
            + semitone_points[left + 1] * fraction
        )
        track.append(REFERENCE * math.pow(2, value / 12))
    return track


class SemitoneTest(unittest.TestCase):
    def test_an_octave_is_twelve_semitones(self) -> None:
        self.assertAlmostEqual(semitones(240.0, 120.0), 12.0, places=6)
        self.assertAlmostEqual(semitones(60.0, 120.0), -12.0, places=6)

    def test_the_same_pitch_is_no_distance(self) -> None:
        self.assertAlmostEqual(semitones(120.0, 120.0), 0.0, places=9)

    def test_silence_has_no_pitch_to_measure(self) -> None:
        with self.assertRaises(ValueError):
            semitones(0.0, 120.0)


class VoicedContourTest(unittest.TestCase):
    def test_unvoiced_frames_are_dropped_not_interpolated(self) -> None:
        # A zero is the tracker saying it found no pitch. Interpolating
        # across it would invent a pitch nobody produced, and an invented
        # dip is exactly what separates third tone from second.
        self.assertEqual(
            voiced_contour([0.0, 100.0, 0.0, 110.0, 120.0, 0.0], trim=0.0),
            [100.0, 110.0, 120.0],
        )

    def test_the_edges_go_where_the_tracker_is_least_sure(self) -> None:
        track = [float(value) for value in range(100, 120)]
        trimmed = voiced_contour(track, trim=0.1)
        self.assertEqual(trimmed[0], 102.0)
        self.assertEqual(trimmed[-1], 117.0)

    def test_a_contour_too_short_to_trim_survives_whole(self) -> None:
        self.assertEqual(voiced_contour([100.0, 110.0]), [100.0, 110.0])


class ClassifyToneTest(unittest.TestCase):
    def test_first_tone_is_high_and_level(self) -> None:
        self.assertEqual(classify_tone(contour([5.0, 5.0]), REFERENCE), TONE_HIGH)

    def test_second_tone_rises(self) -> None:
        self.assertEqual(classify_tone(contour([-2.0, 4.0]), REFERENCE), TONE_RISING)

    def test_third_tone_dips_and_recovers(self) -> None:
        # 214: starts low, falls lower, comes back up.
        self.assertEqual(
            classify_tone(contour([-1.0, -6.0, 1.0]), REFERENCE),
            TONE_DIPPING,
        )

    def test_fourth_tone_falls_from_high_to_low(self) -> None:
        self.assertEqual(classify_tone(contour([6.0, -6.0]), REFERENCE), TONE_FALLING)

    def test_a_rise_that_dipped_first_is_third_not_second(self) -> None:
        # The distinction the whole classifier turns on. Both end above
        # where they are lowest; only the third tone fell to get there.
        rising = classify_tone(contour([-3.0, 3.0]), REFERENCE)
        dipping = classify_tone(contour([1.0, -5.0, 2.0]), REFERENCE)
        self.assertEqual(rising, TONE_RISING)
        self.assertEqual(dipping, TONE_DIPPING)

    def test_a_low_voice_and_a_high_one_read_the_same(self) -> None:
        # Tone is a shape against the speaker's own range. A measurement
        # that returned different tones for the same shape at different
        # pitches would be reading the speaker, not the tone.
        low = [value * 0.5 for value in contour([6.0, -6.0])]
        high = [value * 2.0 for value in contour([6.0, -6.0])]
        self.assertEqual(classify_tone(low, REFERENCE * 0.5), TONE_FALLING)
        self.assertEqual(classify_tone(high, REFERENCE * 2.0), TONE_FALLING)

    def test_a_contour_with_no_pitch_is_unreadable_not_a_guess(self) -> None:
        # Blaming the voice for a tracker that found nothing would make a
        # silent recording look like a mispronouncing one.
        self.assertIsNone(classify_tone([0.0, 0.0, 0.0, 0.0], REFERENCE))
        self.assertIsNone(classify_tone([110.0], REFERENCE))


class ReferencePitchTest(unittest.TestCase):
    def test_the_reference_is_the_median_of_what_was_voiced(self) -> None:
        self.assertEqual(reference_pitch([0.0, 100.0, 120.0, 140.0, 0.0]), 120.0)

    def test_an_even_count_averages_the_middle_pair(self) -> None:
        self.assertEqual(reference_pitch([100.0, 120.0, 140.0, 160.0]), 130.0)

    def test_silence_has_no_reference(self) -> None:
        self.assertIsNone(reference_pitch([0.0, 0.0]))


class ToneAccuracyTest(unittest.TestCase):
    def test_unreadable_probes_do_not_count_as_wrong(self) -> None:
        # A run that could not be measured and a voice that mispronounced
        # everything must not produce the same summary.
        scored = tone_accuracy([(1, 1), (2, None), (3, 3), (4, None)])
        self.assertEqual(scored["correct"], 2)
        self.assertEqual(scored["wrong"], 0)
        self.assertEqual(scored["unreadable"], 2)
        self.assertEqual(scored["accuracy"], 1.0)

    def test_a_wrong_tone_is_wrong(self) -> None:
        scored = tone_accuracy([(1, 4), (2, 2)])
        self.assertEqual(scored["correct"], 1)
        self.assertEqual(scored["wrong"], 1)
        self.assertEqual(scored["accuracy"], 0.5)

    def test_an_empty_run_scores_nothing_rather_than_perfectly(self) -> None:
        self.assertEqual(tone_accuracy([])["accuracy"], 0.0)


class ProbeCorpusTest(unittest.TestCase):
    def test_every_probe_has_a_unique_id(self) -> None:
        ids = [probe.id for probe in all_probes()]
        self.assertEqual(len(ids), len(set(ids)))

    def test_every_expected_reading_names_a_real_tone(self) -> None:
        for probe in all_probes():
            self.assertIn(
                probe.expected_tone,
                {1, 2, 3, 4, 5},
                f"{probe.id} expects tone {probe.expected_tone}",
            )

    def test_the_syllable_under_test_exists_in_the_word(self) -> None:
        for probe in all_probes():
            self.assertLess(
                probe.syllable,
                len(probe.text),
                f"{probe.id} points past the end of {probe.text}",
            )

    def test_a_disagreement_records_both_readings(self) -> None:
        # The point of the Taiwan-reading probes is to say which standard
        # was spoken, which needs both readings on file.
        for probe in probes_by_category()["taiwan-reading"]:
            self.assertIsNotNone(
                probe.mainland,
                f"{probe.id} claims a disagreement without the other reading",
            )
            self.assertNotEqual(probe.expected, probe.mainland)

    def test_the_controls_cover_all_four_tones(self) -> None:
        # The controls exist to catch a broken measurement. Missing a tone
        # would leave the one shape the tracker cannot read untested.
        tones = {probe.expected_tone for probe in probes_by_category()["control"]}
        self.assertEqual(tones, {1, 2, 3, 4})

    def test_the_polyphones_are_paired(self) -> None:
        # Each polyphone appears in both readings. One alone would let a
        # model that has memorised a single reading look correct.
        characters: dict[str, set[str]] = {}
        for probe in probes_by_category()["polyphone"]:
            character = probe.text[probe.syllable]
            characters.setdefault(character, set()).add(probe.expected)
        for character, readings in characters.items():
            self.assertGreaterEqual(
                len(readings), 2, f"{character} is tested in only one reading"
            )


if __name__ == "__main__":
    unittest.main()
