#!/usr/bin/env python3
"""Words the voice says wrongly, respelled into words it says correctly.

The agent's voice mispronounces a specific, small set of words badly enough
that a listener notices and a recogniser cannot recover them: 企業 comes
out as 奇幼, 結構 as 極口, 危險 as 一會兒. Measured, not guessed — see
`sidecars/tone_probe` for how, and
`docs/decisions/taiwan-mandarin-voice-candidates.md` for the run.

The obvious fixes were tried and are gone. The model does not accept pinyin
annotation: `qi1業` renders as 七一一, it reads the digits. Its unquantised
build mispronounces the same words. A different model is better on isolated
words and no better on real sentences while taking twice as long to speak.

What works is spelling the word as a different word that sounds the same.
Writing 氣業 makes the voice say qì yè, which is what 企業 is, and the
recogniser then writes 企業 back — the sound is right and the characters
it was reached through are nobody's business. Every entry below was
verified that way: rendered, transcribed, and accepted only when the
original word came back.

Two rules this must never break.

**Render only.** These respellings exist between the text and the
synthesiser. They must never reach the conversation, storage, or the
screen, or the user will read 氣業 in their own transcript and rightly
conclude the agent cannot spell.

**Same sound, always.** An entry that changes the sound is not a
pronunciation fix, it is the voice saying a different word. That is worse
than the defect it replaces, because it is invisible in text.
"""

from __future__ import annotations

# word -> (respelling, what it said before, what it says now)
#
# The third field is what makes an entry auditable. Without it a future
# reader has a table of substitutions and no way to tell which are still
# needed, and a model upgrade would leave every one of them in place
# forever.
RESPELLINGS: dict[str, tuple[str, str, str]] = {
    "企業": ("氣業", "奇幼", "企業"),
    "危險": ("維險", "吸混", "危險"),
    "攜帶": ("西帶", "頭戴", "攜帶"),
    "品質": ("品直", "品機", "品質"),
    "蝸牛": ("刮牛", "犀牛", "蝸牛"),
    "音樂": ("音月", "音臥", "音樂"),
    "成長": ("成掌", "成整", "成長"),
    "編譯": ("邊譯", "偏西", "編譯"),
    "結構": ("潔構", "極口", "結構"),
    "檸檬": ("寧蒙", "雞蒙", "檸檬"),
    "確認": ("卻認", "誇引", "確認"),
}


def respell(text: str, table: dict[str, tuple[str, str, str]] | None = None) -> str:
    """[text] with every known-mispronounced word swapped for its respelling.

    Longest word first, so an entry that contains another cannot be broken
    in half by it. Everything else is left exactly as written: this is a
    lookup, not a rewriter, and text the table has never been measured
    against must reach the synthesiser untouched.
    """
    entries = table if table is not None else RESPELLINGS
    for word in sorted(entries, key=len, reverse=True):
        if word in text:
            text = text.replace(word, entries[word][0])
    return text


def applied(text: str, table: dict[str, tuple[str, str, str]] | None = None) -> list[str]:
    """Which entries [text] would trigger, for logging what was changed."""
    entries = table if table is not None else RESPELLINGS
    return [word for word in sorted(entries, key=len, reverse=True) if word in text]
