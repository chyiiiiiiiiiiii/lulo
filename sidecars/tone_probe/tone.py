#!/usr/bin/env python3
"""Reading a Mandarin tone off a pitch contour.

Whisper cannot answer the question this file exists for. Ask it to
transcribe a voice that said qǐ yè where Taiwan says qì yè and it returns
企業 either way: its language model repairs the pronunciation before the
text reaches you, so a round trip through ASR proves the word was
recognisable and says nothing at all about whether it was said correctly.
The tone is in the pitch, so the pitch is what has to be measured.

The four tones are shapes, not pitches. Their canonical descriptions in
Chao numerals are 55, 35, 214 and 51: first is high and level, second
rises, third dips low and recovers, fourth falls from high to low. What
matters is the shape relative to the speaker's own range, which is why
everything here is measured in semitones against a reference pitch rather
than in hertz.

Honest limits, because a number that is trusted further than it deserves is
worse than no number:

- This is a comparative instrument. The thresholds below are chosen to
  separate canonical contours, not calibrated against labelled Taiwanese
  speech, so an absolute score of "82% correct" means less than the
  difference between two candidates measured the same way.
- Third tone in running speech is usually a low fall with no recovery, and
  before another third tone it becomes a rising tone outright. Probes are
  therefore isolated words, and the sandhi cases state the tone actually
  expected rather than the citation form.
- A neutral tone carries no shape of its own. It is not classified; probes
  do not target one.
"""

from __future__ import annotations

import math

# Tones, by their conventional numbers.
TONE_HIGH = 1
TONE_RISING = 2
TONE_DIPPING = 3
TONE_FALLING = 4

# Thresholds in semitones.
#
# A semitone is the right unit because pitch is heard proportionally: the
# same tone spoken by a low voice and a high one covers the same number of
# semitones and very different numbers of hertz.
#
# Fourth tone is the steepest movement in the language and the easiest to
# separate, so it is tested first and given the widest margin. Second and
# third both end higher than their lowest point, and what separates them is
# whether the contour fell before it rose.
_FALL_SEMITONES = 2.5
_RISE_SEMITONES = 2.0
_DIP_SEMITONES = 1.5
_RECOVERY_SEMITONES = 0.8
_LEVEL_SEMITONES = 1.5


def semitones(frequency_hz: float, reference_hz: float) -> float:
    """[frequency_hz] as semitones above or below [reference_hz]."""
    if frequency_hz <= 0 or reference_hz <= 0:
        raise ValueError("A pitch in semitones needs two positive frequencies.")
    return 12.0 * math.log2(frequency_hz / reference_hz)


def voiced_contour(
    contour_hz: list[float],
    trim: float = 0.1,
) -> list[float]:
    """The voiced middle of [contour_hz], with its edges trimmed.

    Unvoiced frames arrive as zero from the tracker and carry no pitch, so
    they are dropped rather than interpolated. The first and last [trim] of
    what remains goes too: a syllable's onset and release are where the
    tracker is least sure and where consonant articulation bends the pitch
    for reasons that have nothing to do with the tone.
    """
    voiced = [value for value in contour_hz if value > 0]
    if len(voiced) < 3:
        return voiced
    margin = int(len(voiced) * trim)
    if margin == 0:
        return voiced
    return voiced[margin : len(voiced) - margin]


def classify_tone(
    contour_hz: list[float],
    reference_hz: float,
) -> int | None:
    """Which tone [contour_hz] is, or None when it cannot be read.

    None rather than a guess. A contour too short or too unvoiced to have a
    shape is a measurement failure, and counting it as a wrong tone would
    blame the voice for something the tracker did.
    """
    voiced = voiced_contour(contour_hz)
    if len(voiced) < 3 or reference_hz <= 0:
        return None

    track = [semitones(value, reference_hz) for value in voiced]
    third = max(1, len(track) // 3)
    start = sum(track[:third]) / third
    end = sum(track[-third:]) / third
    lowest = min(track)

    fall = start - end
    rise = end - start
    dip = start - lowest
    recovery = end - lowest

    # Fourth tone: the steep fall. Tested first because it is the only
    # contour that ends far below where it began, and because a third tone
    # that fails to recover would otherwise be mistaken for it.
    if fall >= _FALL_SEMITONES:
        return TONE_FALLING

    # Third tone: fell, then came back. The recovery is what separates it
    # from a second tone, which rises from its start without dipping first.
    if dip >= _DIP_SEMITONES and recovery >= _RECOVERY_SEMITONES:
        return TONE_DIPPING

    # Second tone: rises, and did not dip on the way.
    if rise >= _RISE_SEMITONES:
        return TONE_RISING

    # First tone: goes nowhere. Checked last, so anything with a shape has
    # already been claimed and only the level contour is left.
    if abs(rise) <= _LEVEL_SEMITONES and dip < _DIP_SEMITONES:
        return TONE_HIGH

    # A shape that matched nothing. Reported as unreadable rather than
    # assigned to whichever tone it least resembles.
    return None


def reference_pitch(contour_hz: list[float]) -> float | None:
    """The speaker's own pitch, as the median of every voiced frame.

    Taken across the whole utterance rather than per syllable, because a
    tone is a shape relative to the speaker and a per-syllable reference
    would normalise away the very thing being measured.
    """
    voiced = sorted(value for value in contour_hz if value > 0)
    if not voiced:
        return None
    middle = len(voiced) // 2
    if len(voiced) % 2 == 1:
        return voiced[middle]
    return (voiced[middle - 1] + voiced[middle]) / 2.0


def tone_accuracy(results: list[tuple[int, int | None]]) -> dict[str, float]:
    """Scores a list of (expected tone, measured tone) pairs.

    Unreadable measurements are counted and reported separately rather than
    folded into the error rate. A run where half the probes could not be
    read is not a voice that is half wrong; it is a measurement that did not
    work, and the two must not look the same in a summary.
    """
    total = len(results)
    if total == 0:
        return {"total": 0, "correct": 0, "wrong": 0, "unreadable": 0,
                "accuracy": 0.0, "readable": 0}
    unreadable = sum(1 for _, measured in results if measured is None)
    correct = sum(
        1 for expected, measured in results
        if measured is not None and measured == expected
    )
    readable = total - unreadable
    return {
        "total": total,
        "correct": correct,
        "wrong": readable - correct,
        "unreadable": unreadable,
        "readable": readable,
        # Over readable probes only, for the reason above.
        "accuracy": (correct / readable) if readable else 0.0,
    }
