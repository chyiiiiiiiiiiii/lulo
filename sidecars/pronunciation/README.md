# Pronunciation respelling

A fix for a voice that says the wrong word, without changing the voice.

## The problem

The resident TTS mispronounces a small, specific set of words badly enough
that a recogniser cannot recover them and a listener notices something is
off. Measured — 企業 renders as 奇幼, 結構 as 極口, 危險 as 一會兒. See
`sidecars/tone_probe` for the instrument and
`docs/decisions/taiwan-mandarin-voice-candidates.md` for the run.

## What was tried first, and why it is gone

- **Pinyin annotation.** The model does not accept it. `qi1業` renders as
  七一一 — it reads the digits aloud.
- **The unquantised build.** Same model without 8-bit quantisation scores
  26/37 against the quantised 27/37. The defect is in the model, not its
  compression.
- **A different model.** VoxCPM2 is much better on isolated words (89%
  against 73%) and no better on real sentences (CER 0.087 against 0.093),
  while taking twice as long to speak, on a laptop that is also running the
  model generating those words.

## What works

Spell the word as a different word that sounds the same. Writing 氣業 makes
the voice say qì yè, which is what 企業 is.

Every entry was verified the same way: render `這個詞是X。` with the
respelling, transcribe it, and accept only when the **original** word came
back. That the recogniser writes 企業 having been given audio synthesised
from 氣業 is the evidence — the sound was right enough for a language model
to prefer the real word.

Measured on whole sentences, where it matters:

| Sentence | Before | After |
|---|---|---|
| 危險的操作… | CER 0.214 | 0.111 |
| 品質跟速度… | 0.077 | 0.038 |
| 成長最快的… | 0.074 | 0.019 |
| 好的，我幫你確認… | 0.122 | 0.122 |

The last row is the control, and it is the useful one: 結構 was already
correct in that sentence and the remaining error was 確認, which was not
in the table at the time. The table changes what it was measured on and
nothing else.

## The two rules

**Render only.** The respelling lives between the text and the synthesiser.
It must never reach the conversation, storage, or the screen. A user who
read 氣業 in their own transcript would rightly conclude the agent cannot
spell.

**Same sound, always.** An entry that changes the sound is the voice saying
a different word, which is worse than the defect it replaces because
nothing in the text shows it. The tests enforce equal syllable counts and
that no respelling is itself a table entry.

## Adding an entry

1. Confirm the defect: render `這個詞是X。` and check the transcript.
2. Pick a respelling with the same reading, tone included.
3. Render the respelling and require the **original** word back.
4. Add `word: (respelling, what it said before, the word)` and run the
   tests.

Step 3 is the one that cannot be skipped. A respelling that looks
homophonous on paper and is not simply moves the error somewhere else.

## When to delete this

Every entry records the defect it fixes, so the table is auditable rather
than permanent. After a model change, re-run the probes: any word that no
longer fails should lose its entry. A respelling kept past its usefulness
is a silent substitution for no reason.
