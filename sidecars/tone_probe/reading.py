#!/usr/bin/env python3
"""Comparing what was heard to what should have been said, syllable by syllable.

"The word survived" is a blunt instrument. 企業 coming back as 奇幼 is a
failure, and so is 企業 coming back as 企業 said with the mainland tone,
and the first is far worse than the second — but a match on characters
scores them identically, at zero and one respectively.

Reading the transcript as sound fixes both ends. 奇幼 is qí yòu against an
expected qì yè: the second syllable is a different sound entirely, the
first is the right sound with the wrong tone. That is a diagnosis. It also
gives the tone measurement the pitch tracker was built for, without
needing to find a syllable boundary in a waveform.

The catch, and it is a real one: a recogniser writes down what it decided
was said, not what was said. Its language model repairs whatever it can,
so this understates errors. It cannot overstate them, which is the
direction that matters for a measurement used to choose between voices —
a voice that scores well here has genuinely produced recognisable sound.
"""

from __future__ import annotations


def split_reading(reading: str) -> tuple[str, int | None]:
    """A pinyin syllable split into its sound and its tone.

    `qi4` becomes `("qi", 4)`. A syllable written without a tone digit
    keeps its sound and reports no tone, rather than being assigned one.
    """
    if reading and reading[-1].isdigit():
        return reading[:-1], int(reading[-1])
    return reading, None


def compare_readings(
    expected: list[str],
    heard: list[str],
) -> dict[str, object]:
    """How much of [expected] survives in [heard].

    Compared position by position, and only when the two have the same
    length. A transcript with a different number of syllables is not a
    tone error in one place, it is a different utterance, and lining them
    up would invent a per-syllable story about something that did not
    happen.
    """
    if len(expected) != len(heard):
        return {
            "comparable": False,
            "syllables": len(expected),
            "soundMatches": 0,
            "toneMatches": 0,
            "wrongToneRightSound": 0,
        }
    sounds = 0
    tones = 0
    wrong_tone_right_sound = 0
    for want, got in zip(expected, heard):
        want_sound, want_tone = split_reading(want)
        got_sound, got_tone = split_reading(got)
        if want_sound == got_sound:
            sounds += 1
            if want_tone == got_tone:
                tones += 1
            else:
                wrong_tone_right_sound += 1
    return {
        "comparable": True,
        "syllables": len(expected),
        "soundMatches": sounds,
        "toneMatches": tones,
        # The interesting failure: the right syllable said in the wrong
        # tone. That is an accent, where a wrong sound is a broken word.
        "wrongToneRightSound": wrong_tone_right_sound,
    }


def is_homophone(expected: list[str], heard: list[str]) -> bool:
    """Whether [heard] is the same sound as [expected], tones included.

    Used to accept a deliberate respelling. Writing 氣業 to make a voice
    say qì yè produces a transcript of 氣業, which is the wrong characters
    and exactly the right sound — and the sound is the whole point.
    """
    return len(expected) == len(heard) and all(
        want == got for want, got in zip(expected, heard)
    )


def summarise(rows: list[dict[str, object]]) -> dict[str, object]:
    """Totals over a run's per-probe comparisons."""
    comparable = [row for row in rows if row.get("comparable")]
    syllables = sum(int(row["syllables"]) for row in comparable)
    sounds = sum(int(row["soundMatches"]) for row in comparable)
    tones = sum(int(row["toneMatches"]) for row in comparable)
    wrong_tone = sum(int(row["wrongToneRightSound"]) for row in comparable)
    return {
        "probes": len(rows),
        # A transcript of a different length could not be lined up. Counted
        # rather than dropped, because a voice that produces them often is
        # failing badly and the summary must not hide that as "no data".
        "notComparable": len(rows) - len(comparable),
        "syllables": syllables,
        "soundAccuracy": (sounds / syllables) if syllables else 0.0,
        "toneAccuracy": (tones / syllables) if syllables else 0.0,
        "wrongToneRightSound": wrong_tone,
    }
