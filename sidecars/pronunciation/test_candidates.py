#!/usr/bin/env python3
"""Tests for the automatic respelling proposer.

Skipped where its three dictionaries are not installed, which is the normal
state of the quality gate: everything else in this package imports nothing.
"""

from __future__ import annotations

import unittest

from lexicon import READS_DIFFERENTLY, RESPELLINGS

# The module itself imports nothing; its three dictionaries are pulled in
# when a Proposer is built. So the skip has to ask for them here, or the
# gate fails inside setUpClass instead of skipping.
try:
    import importlib.util

    import pypinyin  # noqa: F401
    from opencc import OpenCC  # noqa: F401

    from candidates import Proposer, misread_inside_a_longer_word

    if importlib.util.find_spec("jieba") is None:
        raise ImportError("jieba is not installed")
    _MISSING = ""
except ImportError as error:  # noqa: BLE001 - reported as a skip reason
    Proposer = None  # type: ignore[assignment]
    _MISSING = str(error)


@unittest.skipUnless(Proposer is not None, f"needs requirements.txt: {_MISSING}")
class ProposerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.proposer = Proposer()

    def test_the_simplified_spelling_comes_last(self) -> None:
        # It is the strongest fix and the one nothing here can check: a
        # recogniser writes 企業 down whether it heard qì yè or qǐ yè, so a
        # whole word rewritten in the script the model was mostly trained
        # on could shift its reading invisibly. A homophone is tone-safe by
        # construction. So Simplified is offered, and offered last.
        for word, simplified in (("開發", "开发"), ("檔案", "档案")):
            proposals = self.proposer.propose(word, limit=12)
            self.assertEqual(proposals[-1], simplified)
            self.assertNotEqual(proposals[0], simplified)

    def test_it_converts_characters_and_not_terms(self) -> None:
        # OpenCC's phrase conversion turns 檔案 into 文件, which is a
        # different word and would be the voice saying something else. The
        # character-level converter is the only correct one here.
        self.assertNotIn("文件", self.proposer.propose("檔案", limit=40))

    def test_every_proposal_keeps_the_syllable_count(self) -> None:
        for word in ("規劃", "訓練", "電子郵件", "頁"):
            for candidate in self.proposer.propose(word, limit=30):
                self.assertEqual(
                    len(word), len(candidate),
                    f"{word} -> {candidate} changes the number of syllables",
                )

    def test_it_never_proposes_the_word_itself(self) -> None:
        for word in ("規劃", "壓力", "瓶頸"):
            self.assertNotIn(word, self.proposer.propose(word, limit=30))

    def test_a_rare_shared_reading_does_not_rank_first(self) -> None:
        # 之 carries a rare zhì beside its ordinary zhī, and 務 a literary
        # wú beside its ordinary wù, so sharing *a* reading put 之量 and
        # 業无 at the front of the queue. Neither sounds like the word, and
        # the bare carrier cannot say so — 之量 is not a word, so the
        # recogniser writes 質量 down from a wrong sound.
        for word in ("質量", "業務", "裝備"):
            first = self.proposer.propose(word, limit=1)[0]
            self.assertEqual(
                self.proposer._sound(first), self.proposer._sound(word),
                f"{word} -> {first} does not read the same way",
            )

    def test_it_cannot_reach_a_taiwan_reading(self) -> None:
        # The boundary of the whole automation, pinned so nobody assumes
        # otherwise. 企業 is qǐ yè in the dictionary and qì yè in Taiwan,
        # and 氣 shares no reading with 企 — so the pool cannot contain the
        # entry that fixes it, 氣業, at any depth. The same goes for 維險
        # (危 wéi against wēi) and 西帶 (攜 xī against xié).
        #
        # This loop fixes a word the voice **destroys**. A word the voice
        # says with the mainland reading is a different defect: the word
        # survives, a recogniser writes it down happily, and only pitch or
        # a pair of ears can see it. That is `sidecars/tone_probe`, and it
        # is where the first eleven entries came from.
        self.assertNotIn("氣業", self.proposer.propose("企業", limit=200))

    def test_no_entry_is_misread_inside_a_longer_word(self) -> None:
        # The table has no segmenter and does not need one while every entry
        # preserves the sound — 記錄 -> 記路 fires inside 登記錄音 and 登記路音
        # is read aloud identically. A polyphone at that boundary is the one
        # case where it is not. 行業 -> 形業 was proposed and rejected here:
        # it fires inside 五金行業, 分行業 and 同行業, where 行 is háng.
        for word, (said, _, _) in RESPELLINGS.items():
            if word in READS_DIFFERENTLY:
                # The dictionary already disagrees with the voice about this
                # word, so it cannot be the judge of a longer one either:
                # it reads 兒童音樂 as lè, which is simply wrong.
                continue
            broken = misread_inside_a_longer_word(word, said, limit=1)
            self.assertEqual(
                broken, [],
                f"{word} -> {said} would say {broken[0][1] if broken else ''} "
                f"where {broken[0][0] if broken else ''} needs "
                f"{broken[0][2] if broken else ''}",
            )

    def test_a_word_gets_a_sentence_that_contains_it(self) -> None:
        # The carrier can convict an innocent word -- 字串 and 檔名 are
        # destroyed in it and perfect in every sentence -- so nothing ships
        # on the carrier alone, and nobody is writing a sentence for the
        # thousandth word by hand.
        for word in ("螢幕", "旅遊", "尷尬", "其實"):
            sentence = self.proposer.sentence_for(word)
            self.assertIn(word, sentence)
            self.assertGreater(len(sentence), len(word) + 4)
            self.assertTrue(sentence.endswith(("。", "？")))

    def test_it_reaches_the_answers_that_were_found_by_hand(self) -> None:
        # The proposer does not have to find the entry somebody chose -- the
        # round trip is the judge and several candidates pass per word. But
        # a pool that could not reach most of them would not be reaching
        # much else either, so this is the floor.
        reached = sum(
            1 for word, (said, _, _) in RESPELLINGS.items()
            if said in self.proposer.propose(word, limit=50)
        )
        self.assertGreaterEqual(
            reached, int(len(RESPELLINGS) * 0.75),
            f"only {reached}/{len(RESPELLINGS)} hand-picked answers are in "
            f"the top 50 proposals",
        )


if __name__ == "__main__":
    unittest.main()
