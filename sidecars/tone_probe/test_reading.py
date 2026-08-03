#!/usr/bin/env python3
"""Tests for comparing a heard reading to the expected one."""

from __future__ import annotations

import unittest

from reading import compare_readings, is_homophone, split_reading, summarise


class SplitReadingTest(unittest.TestCase):
    def test_a_syllable_splits_into_sound_and_tone(self) -> None:
        self.assertEqual(split_reading("qi4"), ("qi", 4))
        self.assertEqual(split_reading("zhang3"), ("zhang", 3))

    def test_a_syllable_with_no_tone_is_not_given_one(self) -> None:
        # Inventing a tone would make an unmarked syllable agree or
        # disagree with something by accident.
        self.assertEqual(split_reading("de"), ("de", None))


class CompareReadingsTest(unittest.TestCase):
    def test_a_perfect_reading_matches_throughout(self) -> None:
        scored = compare_readings(["qi4", "ye4"], ["qi4", "ye4"])
        self.assertEqual(scored["soundMatches"], 2)
        self.assertEqual(scored["toneMatches"], 2)

    def test_the_right_sound_in_the_wrong_tone_is_counted_apart(self) -> None:
        # The whole reason for this file. qì yè said as qǐ yè is an accent;
        # said as qí yòu it is a broken word. Both are wrong and they are
        # not the same kind of wrong.
        scored = compare_readings(["qi4", "ye4"], ["qi3", "ye4"])
        self.assertEqual(scored["soundMatches"], 2)
        self.assertEqual(scored["toneMatches"], 1)
        self.assertEqual(scored["wrongToneRightSound"], 1)

    def test_the_measured_failure_of_the_resident_voice(self) -> None:
        # 企業 came back as 奇幼: qi with the wrong tone, then a different
        # syllable altogether.
        scored = compare_readings(["qi4", "ye4"], ["qi2", "you4"])
        self.assertEqual(scored["soundMatches"], 1)
        self.assertEqual(scored["toneMatches"], 0)
        self.assertEqual(scored["wrongToneRightSound"], 1)

    def test_a_transcript_of_another_length_is_not_lined_up(self) -> None:
        # Comparing position by position across different lengths would
        # invent a per-syllable story about a different utterance.
        scored = compare_readings(["qi4", "ye4"], ["qi4", "ye4", "de"])
        self.assertFalse(scored["comparable"])
        self.assertEqual(scored["soundMatches"], 0)


class HomophoneTest(unittest.TestCase):
    def test_the_same_sound_in_different_characters_is_accepted(self) -> None:
        # Writing 氣業 to make the voice say qì yè is a repair, not a
        # failure: the characters are wrong and the sound is right, and
        # the sound is what a listener gets.
        self.assertTrue(is_homophone(["qi4", "ye4"], ["qi4", "ye4"]))

    def test_a_different_tone_is_not_a_homophone(self) -> None:
        self.assertFalse(is_homophone(["qi4", "ye4"], ["qi3", "ye4"]))


class SummariseTest(unittest.TestCase):
    def test_it_totals_across_probes(self) -> None:
        rows = [
            {"comparable": True, "syllables": 2, "soundMatches": 2,
             "toneMatches": 2, "wrongToneRightSound": 0},
            {"comparable": True, "syllables": 2, "soundMatches": 2,
             "toneMatches": 1, "wrongToneRightSound": 1},
        ]
        scored = summarise(rows)
        self.assertEqual(scored["syllables"], 4)
        self.assertEqual(scored["soundAccuracy"], 1.0)
        self.assertEqual(scored["toneAccuracy"], 0.75)
        self.assertEqual(scored["wrongToneRightSound"], 1)

    def test_transcripts_that_could_not_be_lined_up_are_counted(self) -> None:
        # A voice that produces them often is failing badly, and a summary
        # that reported only "no data" would hide that.
        rows = [
            {"comparable": False, "syllables": 2, "soundMatches": 0,
             "toneMatches": 0, "wrongToneRightSound": 0},
            {"comparable": True, "syllables": 2, "soundMatches": 2,
             "toneMatches": 2, "wrongToneRightSound": 0},
        ]
        scored = summarise(rows)
        self.assertEqual(scored["notComparable"], 1)
        self.assertEqual(scored["toneAccuracy"], 1.0)

    def test_an_empty_run_scores_nothing_rather_than_perfectly(self) -> None:
        self.assertEqual(summarise([])["toneAccuracy"], 0.0)


if __name__ == "__main__":
    unittest.main()
