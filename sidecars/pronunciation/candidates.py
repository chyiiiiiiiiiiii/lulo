# -*- coding: utf-8 -*-
"""Propose respellings for a word automatically, so the table can grow.

The table is a lookup and always will be -- the defect is a property of the
word, not of its characters, so there is no rule to extract. What can be
automated is everything around it: which words to try, what to try instead,
and whether it worked. This is the middle one.

Two sources rank the guesses.

`pypinyin` says which characters share a reading, tone included. That is
what "same sound, always" means, and it is checked rather than trusted --
the round trip is still the judge, because this voice reads some characters
against the dictionary.

Sharing *a* reading is not sharing *the* reading, and the difference bit.
務 is wù and also carries a literary wú, so 无 came out of the pool for it;
質 is zhì and 之 carries a rare zhì, so 之量 was proposed for 質量. Neither
sounds like the word anybody would say, and the bare carrier cannot catch
it -- 之量 is not a word, so the recogniser writes 質量 down from a wrong
sound, the same bias that made 字串 look broken. So a candidate whose
*primary* reading matches the word's is ranked ahead of one that only
shares a rare reading. Ranked, not required: 企業 is qǐ in the dictionary
and qì in Taiwan, so the entry that forces the Taiwan reading, 氣業, would
be thrown out by a strict test and merely sorts late under this one.

`jieba`'s word dictionary gives a character frequency, and the pool is
ranked by it. A rare homophone is a new defect waiting to happen: the voice
is no likelier to say 㰪 correctly than 規. Its dictionary is Simplified, so
a Traditional character is scored by its Simplified form.

The Simplified spelling of the whole word goes **last**, and that ordering
is the one judgement in this file. It is the strongest fix -- it is the same
word rather than a lookalike, and it is what fixed 開發, 檔案, 網頁, 頁 and
蔥薑蒜 when no homophone would -- but it is the one this instrument cannot
check. A homophone is tone-safe by construction, because the pool is built
from characters sharing a reading *including its tone*, and the round trip
then confirms it. Writing a whole word in the script most of the model's
training data used may pull its reading toward the mainland standard, and a
recogniser writes 企業 down whether it heard qì yè or qǐ yè -- so a table
built Simplified-first would trade a defect a listener notices for one the
measurement is blind to. Ranked last, it is only reached when nothing else
works, which is where the five hand-picked ones were reached too.
"""

from __future__ import annotations

import collections
import functools
import pathlib


def _dictionary_path() -> pathlib.Path:
    """Where jieba keeps its word list, without importing jieba.

    Only the data file is wanted. Importing the package runs its own
    `__init__`, which on Python 3.12 reaches for `pkgutil.ImpImporter`
    through an old `pkg_resources` and dies -- and it dies at the point
    where a caller has already paid for a model load.
    """
    import importlib.util
    spec = importlib.util.find_spec("jieba")
    if spec is None or not spec.submodule_search_locations:
        raise ImportError("jieba is not installed; see requirements.txt")
    return pathlib.Path(list(spec.submodule_search_locations)[0]) / "dict.txt"


def _frequency() -> dict[str, int]:
    table: dict[str, int] = collections.Counter()
    path = _dictionary_path()
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        try:
            count = int(parts[1])
        except ValueError:
            continue
        for character in parts[0]:
            table[character] += count
    return table


def _homophones() -> dict[str, list[str]]:
    from pypinyin.constants import PINYIN_DICT
    index: dict[str, list[str]] = collections.defaultdict(list)
    for code, readings in PINYIN_DICT.items():
        for reading in readings.split(","):
            index[reading].append(chr(code))
    return index


# A frame per part of speech, so a word found by machine gets a sentence
# that gives the recogniser real context instead of the bare carrier.
#
# The frames are deliberately dull and conversational -- what matters is
# that the words around the one under test are ordinary and unambiguous, so
# anything the recogniser gets wrong is the word and not the frame. A
# hand-written sentence is still better and the ones in `corpus.py` stay;
# this is what makes a thousand-word sweep possible at all.
_FRAMES: dict[str, str] = {
    "n": "這個{}我幫你看過了。",
    "nz": "這個{}我幫你看過了。",
    "ns": "這個{}我幫你看過了。",
    "vn": "他剛剛說到{}這件事。",
    "an": "他剛剛說到{}這件事。",
    "v": "這件事要不要先{}一下？",
    "vd": "這件事要不要先{}一下？",
    "a": "這樣會不會太{}了？",
    "ad": "這樣會不會太{}了？",
    "d": "{}我覺得這樣就可以了。",
    "t": "{}我們再約一次好不好？",
}
_FALLBACK = "他剛剛提到{}的時候我沒聽清楚。"


def _parts_of_speech() -> dict[str, str]:
    table: dict[str, str] = {}
    for line in _dictionary_path().read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) >= 3:
            table.setdefault(parts[0], parts[2])
    return table


class Proposer:
    """Ranked respellings for one word, best guess first."""

    def __init__(self) -> None:
        from opencc import OpenCC
        self._to_simplified = OpenCC("tw2s").convert
        self._frequency = _frequency()
        self._homophones = _homophones()
        from pypinyin.constants import PINYIN_DICT
        self._readings = {
            chr(code): value.split(",") for code, value in PINYIN_DICT.items()
        }
        self._parts = _parts_of_speech()

    def sentence_for(self, word: str) -> str:
        """A dull, natural sentence to hear [word] inside.

        The carrier 這個詞是X。 finds a defect and cannot clear one -- it
        hands the recogniser no context, so a word said perfectly can come
        back wrong. Nothing can be shipped on the carrier alone, and
        nobody is going to write a sentence for the thousandth word.
        """
        tag = self._parts.get(self._to_simplified(word), "")
        return _FRAMES.get(tag, _FALLBACK).format(word)

    def _sound(self, text: str) -> tuple[str, ...]:
        """How the dictionary reads [text], in context, tone included."""
        from pypinyin import Style, lazy_pinyin
        return tuple(lazy_pinyin(text, style=Style.TONE3,
                                 neutral_tone_with_five=True))

    def _rank(self, character: str) -> int:
        simplified = self._to_simplified(character)
        return self._frequency.get(simplified, self._frequency.get(character, 0))

    def propose(self, word: str, limit: int = 12) -> list[str]:
        """Up to [limit] respellings of [word], commonest characters first."""
        out: list[str] = []
        want = self._sound(word)
        swaps: list[tuple[int, int, str]] = []
        for index, character in enumerate(word):
            for reading in self._readings.get(character, []):
                for other in self._homophones.get(reading, []):
                    if other == character or self._to_simplified(other) == \
                            self._to_simplified(character):
                        continue
                    candidate = word[:index] + other + word[index + 1:]
                    same = 1 if self._sound(candidate) == want else 0
                    swaps.append((same, self._rank(other), candidate))
        swaps.sort(key=lambda triple: (-triple[0], -triple[1]))
        for _, _, candidate in swaps:
            if candidate not in out:
                out.append(candidate)
            if len(out) >= limit - 1:
                break
        simplified = self._to_simplified(word)
        if simplified != word and simplified not in out:
            out.append(simplified)
        return out


@functools.lru_cache(maxsize=1)
def _longer_words() -> tuple[str, ...]:
    """Every dictionary word, once, cached.

    Read per entry this was three and a half seconds a call and five
    minutes for the table, which is not a thing anybody runs.
    """
    words: list[str] = []
    for line in _dictionary_path().read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if parts and 2 <= len(parts[0]) <= 6:
            words.append(parts[0])
    return tuple(words)


def misread_inside_a_longer_word(
    word: str, said: str, limit: int = 3
) -> list[tuple[str, str, str]]:
    """Where [said] would be spoken wrongly because [word] is a substring.

    The table has no segmenter, and it does not need one as long as every
    entry preserves the sound: 記錄 -> 記路 fires inside 登記錄音 too, and
    登記路音 is read aloud identically. A polyphone at that boundary is the
    one case where it is not -- 行業 -> 形業 fires inside 五金行業, where 行
    is háng and 形 is xíng, and the voice says a word nobody wrote.

    Returns `(the longer word, what it would say, what it should say)` for
    up to [limit] dictionary words that would break, or an empty list when
    the entry is safe anywhere it lands. The dictionary is Simplified and
    the search is done there: converting three hundred thousand words to
    compare against a Traditional table costs more than it settles, and a
    reading is a property of the character in either script.
    """
    from opencc import OpenCC
    from pypinyin import Style, lazy_pinyin

    to_simplified = OpenCC("tw2s").convert

    def sound(text: str) -> list[str]:
        return lazy_pinyin(text, style=Style.TONE3, neutral_tone_with_five=True)

    changed = {index for index, (a, b) in enumerate(zip(word, said)) if a != b}
    if not changed:
        return []
    simplified = to_simplified(word)
    if len(simplified) != len(word):
        return []
    own = sound(simplified)
    found: list[tuple[str, str, str]] = []
    for longer in _longer_words():
        if len(longer) <= len(simplified) or simplified not in longer:
            continue
        at = longer.index(simplified)
        readings = sound(longer)
        if len(readings) != len(longer):
            continue
        for index in changed:
            if readings[at + index] != own[index]:
                found.append((longer, readings[at + index], own[index]))
                break
        if len(found) >= limit:
            break
    return found
