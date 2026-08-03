#!/usr/bin/env python3
"""Did the voice say the word, and if not, what did it say instead.

The measurement that actually works. Sending a rendered probe back through
a recogniser sounds circular -- a language model repairing a mispronounced
word is the standard objection -- and the carrier sentence is what removes
it. "這個詞是X。" gives the recogniser grammar and no semantics, so it has
nothing to repair X from and writes down what it heard.

Measured on the resident voice: 這個詞是企業。 came back as 这个词是奇幼.
The four carrier characters are perfect and the word under test is
unrecognisable, which is the complaint this whole exercise started from,
caught automatically.

What this does not measure: a word said with the mainland reading is still
the right word, and a recogniser trained on both will write it down
correctly. So this catches a mispronunciation bad enough to destroy the
word, and says nothing about qì yè versus qǐ yè. That distinction needs
the pitch, or a pair of ears.
"""

from __future__ import annotations

# Characters that differ between the scripts and appear in the probes or in
# what a recogniser is likely to return for them.
#
# A full conversion table belongs in OpenCC, which the recogniser sidecar
# already carries. This is only the fallback for scoring somewhere OpenCC
# is not installed, and it is deliberately small: a table that silently
# misses a character would turn a correct render into a failure.
_SIMPLIFIED_TO_TRADITIONAL = {
    "这": "這", "个": "個", "词": "詞", "话": "話", "电": "電",
    "业": "業", "企": "企", "危": "危", "险": "險", "携": "攜",
    "带": "帶", "液": "液", "体": "體", "曝": "曝", "垃": "垃",
    "圾": "圾", "星": "星", "期": "期", "质": "質", "蜗": "蝸",
    "银": "銀", "行": "行", "动": "動", "乐": "樂", "音": "音",
    "快": "快", "重": "重", "要": "要", "复": "複", "长": "長",
    "度": "度", "成": "成", "为": "為", "认": "認", "模": "模",
    "型": "型", "框": "框", "架": "架", "部": "部", "署": "署",
    "编": "編", "译": "譯", "演": "演", "算": "算", "法": "法",
    "数": "數", "据": "據", "执": "執", "结": "結", "构": "構",
    "妈": "媽", "柠": "檸", "檬": "檬", "水": "水", "果": "果",
    "一": "一", "不": "不", "对": "對", "好": "好", "你": "你",
    "天": "天", "起": "起",
}


def to_traditional(text: str, converter=None) -> str:
    """[text] in Traditional characters.

    Takes an OpenCC converter when the caller has one, because that is the
    real answer and the table above is only a fallback.
    """
    if converter is not None:
        return converter.convert(text)
    return "".join(_SIMPLIFIED_TO_TRADITIONAL.get(ch, ch) for ch in text)


def strip_punctuation(text: str) -> str:
    """[text] without punctuation or spacing, in either script's forms."""
    drop = set(" \t\n，。、！？：；「」『』,.!?:;\"'（）()…—-")
    return "".join(ch for ch in text if ch not in drop)


def heard_word(
    transcript: str,
    word: str,
    converter=None,
) -> bool:
    """Whether [word] survives in [transcript].

    Compared in Traditional and without punctuation, because the recogniser
    returns Simplified and punctuates as it likes, and neither is anything
    to do with whether the voice said the word.
    """
    return strip_punctuation(to_traditional(word, converter)) in strip_punctuation(
        to_traditional(transcript, converter)
    )


def what_was_heard_instead(
    transcript: str,
    carrier: str,
    word: str,
    converter=None,
) -> str:
    """The part of [transcript] where [word] should have been.

    The carrier is fixed and known, so whatever the recogniser wrote that
    is not the carrier is its account of the word. Returned so a failure
    reads as "said 奇幼 for 企業" rather than only "wrong", which is the
    difference between a number and a diagnosis.
    """
    said = strip_punctuation(to_traditional(transcript, converter))
    prefix = strip_punctuation(to_traditional(carrier.split(word)[0], converter))
    if prefix and said.startswith(prefix):
        return said[len(prefix):]
    return said


def score_probes(results: list[tuple[str, bool]]) -> dict[str, object]:
    """Counts how many probes came back as the word they were.

    [results] is (probe id, whether the word was heard).
    """
    total = len(results)
    heard = sum(1 for _, ok in results if ok)
    return {
        "total": total,
        "heard": heard,
        "lost": total - heard,
        "intelligibility": (heard / total) if total else 0.0,
        "lostIds": [probe_id for probe_id, ok in results if not ok],
    }
