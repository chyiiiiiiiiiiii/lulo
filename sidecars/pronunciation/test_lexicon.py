#!/usr/bin/env python3
"""Tests for the pronunciation respelling table."""

from __future__ import annotations

import unittest

from corpus import every_sentence, screen_words
from lexicon import READS_DIFFERENTLY, RESPELLINGS, applied, respell

try:
    from pypinyin import Style, lazy_pinyin
    _NO_PINYIN = ""
except ImportError as error:  # noqa: BLE001 - reported as a skip reason
    lazy_pinyin = None  # type: ignore[assignment]
    _NO_PINYIN = str(error)



class RespellTest(unittest.TestCase):
    def test_a_known_word_is_swapped(self) -> None:
        self.assertEqual(respell("這家企業"), "這家氣業")

    def test_text_with_nothing_in_the_table_is_untouched(self) -> None:
        # A lookup, not a rewriter. Text this table has never been measured
        # against must reach the synthesiser exactly as written.
        original = "今天天氣不錯，我們出去走走。"
        self.assertEqual(respell(original), original)

    def test_every_occurrence_is_swapped(self) -> None:
        self.assertEqual(
            respell("企業跟企業之間"), "氣業跟氣業之間"
        )

    def test_several_words_in_one_sentence(self) -> None:
        self.assertEqual(
            respell("危險的操作跟品質有關"),
            "維險的操作跟品直有關",
        )

    def test_nothing_written_is_read_again(self) -> None:
        # A respelling is not text the table gets to look at. With rounds of
        # str.replace, 甲乙 became 丙丁 and then the second entry read the
        # 丁 that the first one had just written.
        table = {
            "甲乙": ("丙丁", "?", "甲乙"),
            "丁": ("戊", "?", "丁"),
        }
        self.assertEqual(respell("甲乙", table), "丙丁")

    def test_overlapping_entries_take_the_leftmost(self) -> None:
        # 檢查 and 查詢 share a character and both are in the table. Applied
        # as rounds of replace the answer depended on which came out of the
        # dictionary first; one pass from the left has only one answer.
        table = {
            "檢查": ("減查", "見察", "檢查"),
            "查詢": ("茶詢", "插身", "查詢"),
        }
        self.assertEqual(respell("檢查詢問", table), "減查詢問")
        self.assertEqual(respell("我要查詢", table), "我要茶詢")

    def test_the_longest_word_wins(self) -> None:
        # An entry contained inside another must not cut it in half. With a
        # table where both 品質 and 品質管理 exist, the longer one has to be
        # matched first or the result is a respelling of a respelling.
        table = {
            "品質": ("品直", "品機", "品質"),
            "品質管理": ("品直管理", "品機管理", "品質管理"),
        }
        self.assertEqual(respell("品質管理", table), "品直管理")


class AppliedTest(unittest.TestCase):
    def test_it_names_what_would_change(self) -> None:
        self.assertEqual(applied("這家企業很危險"), ["企業", "危險"])

    def test_nothing_matched_is_an_empty_list(self) -> None:
        self.assertEqual(applied("今天天氣不錯"), [])


class TableTest(unittest.TestCase):
    def test_no_entry_respells_a_word_as_itself(self) -> None:
        for word, (respelling, _, _) in RESPELLINGS.items():
            self.assertNotEqual(
                word, respelling, f"{word} is respelled as itself"
            )

    def test_every_respelling_is_the_same_length(self) -> None:
        # Same sound means the same syllables. A respelling of a different
        # length is a different utterance, and this table is the one place
        # where that would be silent -- it changes what is spoken and
        # nothing in the transcript shows it.
        for word, (respelling, _, _) in RESPELLINGS.items():
            self.assertEqual(
                len(word), len(respelling),
                f"{word} -> {respelling} changes the number of syllables",
            )

    def test_every_entry_records_what_it_fixed(self) -> None:
        # The evidence is what makes an entry auditable. Without it a
        # future reader has a table of substitutions and no way to tell
        # which are still needed after a model upgrade.
        for word, (_, before, after) in RESPELLINGS.items():
            self.assertTrue(before, f"{word} does not say what it said before")
            self.assertEqual(
                after, word,
                f"{word} claims to produce {after}, which is not the word",
            )
            self.assertNotEqual(
                before, word, f"{word} records no defect and needs no entry"
            )

    def test_every_entry_was_measured_on_something(self) -> None:
        # An entry with nothing to render it in is an entry nobody can
        # re-check after a model upgrade. The corpus is the evidence, so
        # adding a word to the table means adding a sentence for it.
        blob = "".join(every_sentence())
        for word in RESPELLINGS:
            self.assertIn(
                word, blob, f"{word} is in the table and in no sentence"
            )

    def test_the_screen_covers_the_table(self) -> None:
        # The broad screen is what finds a defect in the first place. A
        # table word missing from it would be one somebody added by hand.
        screen = set(screen_words())
        for word in RESPELLINGS:
            self.assertIn(
                word, screen, f"{word} is in the table and not in the screen"
            )

    @unittest.skipUnless(lazy_pinyin is not None, f"needs pypinyin: {_NO_PINYIN}")
    def test_a_respelling_reads_the_same_or_says_why_not(self) -> None:
        def sound(text: str) -> tuple[str, ...]:
            return tuple(lazy_pinyin(text, style=Style.TONE3,
                                     neutral_tone_with_five=True))

        for word, (said, _, _) in RESPELLINGS.items():
            if sound(word) == sound(said):
                self.assertNotIn(
                    word, READS_DIFFERENTLY,
                    f"{word} -> {said} reads the same; drop its exception",
                )
                continue
            self.assertIn(
                word, READS_DIFFERENTLY,
                f"{word} -> {said} reads {'/'.join(sound(said))} against "
                f"{'/'.join(sound(word))} and gives no reason",
            )

    def test_no_respelling_is_itself_a_word_in_the_table(self) -> None:
        # Otherwise applying the table twice, or in the wrong order, would
        # respell a respelling and land somewhere nobody measured.
        respellings = {value[0] for value in RESPELLINGS.values()}
        self.assertEqual(respellings & set(RESPELLINGS), set())

    def test_applying_the_table_twice_changes_nothing_further(self) -> None:
        # The property that follows, checked directly: rendering is not the
        # only caller and one of them will eventually apply this twice.
        for word in RESPELLINGS:
            once = respell(word)
            self.assertEqual(respell(once), once, f"{word} respells twice")


if __name__ == "__main__":
    unittest.main()
