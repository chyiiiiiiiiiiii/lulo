#!/usr/bin/env python3
"""Tests for scoring a probe by what came back through the recogniser."""

from __future__ import annotations

import unittest

from probes import all_probes
from scoring import (
    heard_word,
    score_probes,
    strip_punctuation,
    to_traditional,
    what_was_heard_instead,
)


class ScriptTest(unittest.TestCase):
    def test_a_simplified_transcript_is_read_as_traditional(self) -> None:
        # The recogniser returns Simplified. Comparing scripts rather than
        # words would fail every probe and blame the voice for it.
        self.assertEqual(to_traditional("这个词是企业"), "這個詞是企業")

    def test_an_opencc_converter_is_used_when_it_is_offered(self) -> None:
        class Converter:
            def convert(self, text: str) -> str:
                return text.replace("业", "業")

        self.assertEqual(to_traditional("企业", Converter()), "企業")

    def test_punctuation_is_not_part_of_the_word(self) -> None:
        self.assertEqual(strip_punctuation("這個詞是，企業。"), "這個詞是企業")


class HeardWordTest(unittest.TestCase):
    def test_the_word_coming_back_is_a_pass(self) -> None:
        self.assertTrue(heard_word("这个词是企业。", "企業"))

    def test_the_word_coming_back_wrong_is_a_failure(self) -> None:
        # The real measured case: the resident voice's 企業 was written
        # down as 奇幼.
        self.assertFalse(heard_word("这个词是奇幼", "企業"))

    def test_punctuation_and_script_do_not_decide_it(self) -> None:
        self.assertTrue(heard_word("這個詞是，企業！", "企業"))


class WhatWasHeardInsteadTest(unittest.TestCase):
    def test_it_returns_the_part_the_word_should_have_been(self) -> None:
        # A diagnosis, not a verdict: "said 奇幼" is actionable in a way
        # that "wrong" is not.
        self.assertEqual(
            what_was_heard_instead("这个词是奇幼", "這個詞是企業。", "企業"),
            "奇幼",
        )

    def test_a_transcript_that_lost_the_carrier_returns_all_of_itself(self) -> None:
        # When even the carrier did not survive, nothing can be located
        # inside it, and the whole transcript is the honest answer.
        self.assertEqual(
            what_was_heard_instead("完全不同的東西", "這個詞是企業。", "企業"),
            "完全不同的東西",
        )


class ScoreProbesTest(unittest.TestCase):
    def test_it_counts_and_names_what_was_lost(self) -> None:
        scored = score_probes([("a", True), ("b", False), ("c", True)])
        self.assertEqual(scored["heard"], 2)
        self.assertEqual(scored["lost"], 1)
        self.assertEqual(scored["lostIds"], ["b"])
        self.assertAlmostEqual(scored["intelligibility"], 2 / 3)

    def test_an_empty_run_scores_nothing_rather_than_perfectly(self) -> None:
        self.assertEqual(score_probes([])["intelligibility"], 0.0)


class CarrierTest(unittest.TestCase):
    def test_the_carrier_contains_the_word(self) -> None:
        for probe in all_probes():
            self.assertIn(probe.text, probe.carrier)

    def test_the_carrier_gives_no_semantic_clue_to_the_word(self) -> None:
        # If the sentence hinted at the word, a recogniser could repair a
        # mispronunciation from context and the measurement would report a
        # voice that is better than it is. The carrier is the same four
        # characters every time, and says only that a word follows.
        carriers = {probe.carrier.replace(probe.text, "") for probe in all_probes()}
        self.assertEqual(carriers, {"這個詞是。"})


if __name__ == "__main__":
    unittest.main()
