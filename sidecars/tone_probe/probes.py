#!/usr/bin/env python3
"""The words a Taiwan Mandarin voice is most likely to get wrong.

The complaint this exists to measure is that the agent's voice "sounds a
little off on some nouns and some characters". That is not random. Three
things produce it, and they are separable:

1. Taiwan and mainland standards disagree about the reading of a word that
   is spelled identically. 企業 is qì yè here and qǐ yè there; 垃圾 is
   lè sè here and lā jī there. A model trained mostly on mainland speech
   will confidently produce the mainland reading, which is not an error to
   its own ear and is immediately wrong to a Taiwanese one.
2. Polyphones (破音字) whose reading depends on meaning: 行 as háng in
   銀行 and xíng in行動. Getting this wrong needs no accent, only a
   grapheme-to-phoneme mistake.
3. 一 and 不 change tone according to what follows. These are the most
   frequent words in the language, so a model that handles them loosely is
   wrong constantly rather than occasionally.

Each probe names the syllable under test and the reading Taiwan expects, so
a measurement can say which of the three is failing rather than only that
something sounds off.

`text` is deliberately the bare word. Tone is measured from the pitch
contour of one syllable, and a syllable is only reliably locatable when the
utterance is short. Carrier sentences are a separate, harder measurement;
see `README.md` for what this therefore does not prove.
"""

from __future__ import annotations

# Category names, kept as constants so a typo cannot silently create a new
# category that summaries then report as its own row.
TAIWAN_READING = "taiwan-reading"
POLYPHONE = "polyphone"
SANDHI = "sandhi"
TECH_NOUN = "tech-noun"
CONTROL = "control"


class Probe:
    """One word under test, with the reading Taiwan expects of it."""

    def __init__(
        self,
        probe_id: str,
        text: str,
        syllable: int,
        expected: str,
        category: str,
        note: str,
        mainland: str | None = None,
    ) -> None:
        self.id = probe_id
        self.text = text
        # Index into the syllables of `text`, zero-based.
        self.syllable = syllable
        # Taiwan's expected reading of that syllable, pinyin with a tone
        # digit: 1-4, or 5 for the neutral tone.
        self.expected = expected
        self.category = category
        self.note = note
        # The mainland reading, where the two standards disagree. Recorded
        # so a failure can be reported as "said the mainland reading"
        # rather than the far less useful "said something else".
        self.mainland = mainland

    @property
    def carrier(self) -> str:
        """The word inside a sentence that tells a listener nothing.

        Two reasons the word is never rendered on its own. A cloning model
        given two characters is far outside what it was trained on and
        produces junk -- measured: 檸檬 alone came back as 3.28 seconds
        containing three separate bursts. And a sentence with meaning lets
        a recogniser repair the pronunciation from context, which is
        exactly the evidence being looked for. "This word is X" supplies
        grammar and no clue, so what comes back is what was said.
        """
        return f"這個詞是{self.text}。"

    @property
    def expected_tone(self) -> int:
        """The tone digit of [expected]."""
        return int(self.expected[-1])

    @property
    def mainland_tone(self) -> int | None:
        """The tone digit of the mainland reading, when there is one."""
        return None if self.mainland is None else int(self.mainland[-1])

    def as_dict(self) -> dict[str, object]:
        """A JSON-compatible view, for the evidence file."""
        return {
            "id": self.id,
            "text": self.text,
            "syllable": self.syllable,
            "expected": self.expected,
            "expectedTone": self.expected_tone,
            "mainland": self.mainland,
            "mainlandTone": self.mainland_tone,
            "category": self.category,
            "note": self.note,
        }


# Where the two standards disagree.
#
# These are the ones a Taiwanese listener notices immediately, and every one
# of them is a word an agent would plausibly say out loud.
_TAIWAN_READINGS = [
    Probe(
        "tw-qiye", "企業", 0, "qi4", TAIWAN_READING,
        "Taiwan reads 企 fourth tone; the mainland reads it third.",
        mainland="qi3",
    ),
    Probe(
        "tw-weixian", "危險", 0, "wei2", TAIWAN_READING,
        "Taiwan reads 危 second tone; the mainland reads it first.",
        mainland="wei1",
    ),
    Probe(
        "tw-xiedai", "攜帶", 0, "xi1", TAIWAN_READING,
        "Taiwan reads 攜 as xī; the mainland reads it xié.",
        mainland="xie2",
    ),
    Probe(
        "tw-yeti", "液體", 0, "yi4", TAIWAN_READING,
        "Taiwan reads 液 as yì; the mainland reads it yè.",
        mainland="ye4",
    ),
    Probe(
        "tw-puguang", "曝光", 0, "pu4", TAIWAN_READING,
        "Taiwan reads 曝 as pù; the mainland commonly reads bào.",
        mainland="bao4",
    ),
    Probe(
        "tw-lese", "垃圾", 0, "le4", TAIWAN_READING,
        "Taiwan says lè sè; the mainland says lā jī. Both syllables differ.",
        mainland="la1",
    ),
    Probe(
        "tw-xingqi", "星期", 1, "qi2", TAIWAN_READING,
        "Taiwan reads 期 second tone; the mainland reads it first.",
        mainland="qi1",
    ),
    Probe(
        "tw-pinzhi", "品質", 1, "zhi2", TAIWAN_READING,
        "Taiwan reads 質 second tone; the mainland reads it fourth.",
        mainland="zhi4",
    ),
    Probe(
        "tw-woniu", "蝸牛", 0, "gua1", TAIWAN_READING,
        "Taiwan reads 蝸 as guā; the mainland reads wō.",
        mainland="wo1",
    ),
    Probe(
        "tw-xiaoshi", "microsecond placeholder", 0, "wei2", TAIWAN_READING,
        "Placeholder replaced below; kept out of the exported set.",
    ),
]
# The placeholder above exists only to make the omission obvious if the list
# is ever edited carelessly. It is removed rather than shipped.
_TAIWAN_READINGS = [p for p in _TAIWAN_READINGS if p.id != "tw-xiaoshi"]


# Polyphones, where meaning selects the reading.
#
# Paired deliberately: the same character in both of its readings, so a
# model that has simply memorised one reading scores well on one member of
# the pair and badly on the other, which is visible in a way that a single
# probe would hide.
_POLYPHONES = [
    Probe(
        "poly-yinhang", "銀行", 1, "hang2", POLYPHONE,
        "行 is háng in a bank and xíng in movement.",
    ),
    Probe(
        "poly-xingdong", "行動", 0, "xing2", POLYPHONE,
        "The other half of the 行 pair.",
    ),
    Probe(
        "poly-yinyue", "音樂", 1, "yue4", POLYPHONE,
        "樂 is yuè in music and lè in happiness.",
    ),
    Probe(
        "poly-kuaile", "快樂", 1, "le4", POLYPHONE,
        "The other half of the 樂 pair.",
    ),
    Probe(
        "poly-zhongyao", "重要", 0, "zhong4", POLYPHONE,
        "重 is zhòng in important and chóng in repeat.",
    ),
    Probe(
        "poly-chongfu", "重複", 0, "chong2", POLYPHONE,
        "The other half of the 重 pair.",
    ),
    Probe(
        "poly-changdu", "長度", 0, "chang2", POLYPHONE,
        "長 is cháng in length and zhǎng in growth.",
    ),
    Probe(
        "poly-chengzhang", "成長", 1, "zhang3", POLYPHONE,
        "The other half of the 長 pair.",
    ),
    Probe(
        "poly-weile", "為了", 0, "wei4", POLYPHONE,
        "為 is wèi for purpose and wéi for acting as.",
    ),
    Probe(
        "poly-renwei", "認為", 1, "wei2", POLYPHONE,
        "The other half of the 為 pair.",
    ),
]


# 一 and 不 take their tone from what follows them.
#
# The most frequent words in the language, so looseness here is not an
# occasional blemish; it is audible in almost every sentence.
_SANDHI = [
    Probe(
        "sandhi-yige", "一個", 0, "yi2", SANDHI,
        "一 before a fourth tone becomes second.",
    ),
    Probe(
        "sandhi-yiqi", "一起", 0, "yi4", SANDHI,
        "一 before a third tone becomes fourth.",
    ),
    Probe(
        "sandhi-yitian", "一天", 0, "yi4", SANDHI,
        "一 before a first tone becomes fourth.",
    ),
    Probe(
        "sandhi-budui", "不對", 0, "bu2", SANDHI,
        "不 before a fourth tone becomes second.",
    ),
    Probe(
        "sandhi-buhao", "不好", 0, "bu4", SANDHI,
        "不 before a third tone stays fourth.",
    ),
    Probe(
        "sandhi-nihao", "你好", 0, "ni2", SANDHI,
        "Third plus third: the first becomes a rising tone.",
    ),
]


# Words the agent actually says.
#
# An assistant that talks about its own work says these constantly, and a
# wrong reading here is the one the user hears most often.
_TECH_NOUNS = [
    Probe(
        "tech-moxing", "模型", 0, "mo2", TECH_NOUN,
        "模 is mó here, not mú.",
    ),
    Probe(
        "tech-kuangjia", "框架", 0, "kuang4", TECH_NOUN,
        "Taiwan reads 框 fourth tone.",
        mainland="kuang1",
    ),
    Probe(
        "tech-bushu", "部署", 1, "shu3", TECH_NOUN,
        "署 is shǔ; often heard as shù.",
    ),
    Probe(
        "tech-bianyi", "編譯", 1, "yi4", TECH_NOUN,
        "譯 is yì.",
    ),
    Probe(
        "tech-yansuanfa", "演算法", 0, "yan3", TECH_NOUN,
        "Taiwan says 演算法 where the mainland says 算法.",
    ),
    Probe(
        "tech-shuju", "數據", 0, "shu4", TECH_NOUN,
        "數 is shù as a noun, shǔ as a verb.",
    ),
    Probe(
        "tech-zhixing", "執行", 1, "xing2", TECH_NOUN,
        "行 again, in the word an agent says about itself most.",
    ),
    Probe(
        "tech-jiegou", "結構", 0, "jie2", TECH_NOUN,
        "結 is jié here.",
    ),
]


# Unambiguous words, one per tone.
#
# The control group. If a model scores badly on these, the measurement is
# reading the audio wrongly and nothing else in the run can be believed.
_CONTROLS = [
    Probe("ctl-tone1", "媽媽", 0, "ma1", CONTROL, "A clear first tone."),
    Probe("ctl-tone2", "檸檬", 0, "ning2", CONTROL, "A clear second tone."),
    Probe("ctl-tone3", "水果", 0, "shui3", CONTROL, "A clear third tone."),
    Probe("ctl-tone4", "電話", 0, "dian4", CONTROL, "A clear fourth tone."),
]


def all_probes() -> list[Probe]:
    """Every probe, controls first so a bad run fails loudly and early."""
    return [*_CONTROLS, *_TAIWAN_READINGS, *_POLYPHONES, *_SANDHI, *_TECH_NOUNS]


def probes_by_category() -> dict[str, list[Probe]]:
    """The probes grouped by what they are testing."""
    grouped: dict[str, list[Probe]] = {}
    for probe in all_probes():
        grouped.setdefault(probe.category, []).append(probe)
    return grouped
