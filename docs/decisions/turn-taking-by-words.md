# Who is talking, decided by what was said

Status: adopted. 2026-08-05. Reasoned against the private zh-TW corpus at
`benchmarks/voice_eval/corpus/zh-TW-v1.json` and the measurements recorded in
[voice-turn-latency.md](voice-turn-latency.md).

## The two thresholds, and what they could not tell apart

Both ends of a turn were governed by a threshold on length, and length is
the one signal that separates neither pair it was asked to.

**Taking the floor back.** While the agent spoke, four characters of speech
took the floor. That number exists because one character used to, and one
character let "OK" end an answer 571 characters into being read aloud. But
four is wrong in both directions at once:

| Heard while the agent speaks | Length | Was | Should be |
|---|---:|---|---|
| 對對對對對 | 5 | interrupts | agreement — carry on |
| 嗯嗯 | 2 | ignored | agreement — carry on |
| 不對 | 2 | ignored | stop, immediately |
| 等等 | 2 | ignored | stop, immediately |
| the | 3 | interrupts | one English article |
| 計 (misheard 肌) | 1 | ignored | correct, but only by luck |

The two populations overlap completely on length. 「對對對對對」 is longer
than 「不對」 and means the opposite.

**Giving the floor up.** The endpointer submitted a turn after 0.8s of
silence. The corpus's mid-utterance pauses reach 1.02s and 1.10s, so those
two turns were cut in half — and
[voice-turn-latency.md](voice-turn-latency.md) records that Smart Turn v3.2
cannot separate them either: mid-sentence pauses scored 0.973–0.988 against
0.978–0.989 for real endings, with no threshold between them. That overlap
was already being patched, by a hardcoded list of three phrases
(「等一下」「我想問的是」「我想說的是」) inside `SpeechTurn`.

## What does separate them is the words

The hardcoded three were the right idea at the wrong size. Both decisions
are now lexicons.

### `FloorControl` — `packages/agent_core/lib/src/voice/floor_control.dart`

Classifies an utterance as `backchannel`, `correction`, `substance`, or
`silence`, and only then applies a size.

- **Backchannel** never takes the floor from a speaking agent, at any
  length. Built two ways: a set of runes that can stand alone and repeat
  (嗯 對 好 是 喔 哈 …), so 對對對對對 is agreement by construction rather than
  by enumeration; plus whole phrases that are not built from them (了解,
  原來如此, got it, uh-huh).
- **Correction** takes the floor immediately, at any length. Matched as a
  *prefix* in Han (不對 等等 停 錯了 …) because a correction rarely arrives
  alone — 「不對，我是說……」 is the common shape and waiting for it to finish
  is waiting through the sentence it is trying to stop. Matched by *first
  word* in Latin (wait, stop, no, hold), because "no" has to interrupt and
  "nothing" must not, which prefix matching cannot tell apart.
- **Substance** interrupts at three syllables. A syllable, not a character:
  a run of Latin letters counts once however long it is. Counting runes
  charged "the" as three units of interruption and 「你可以解釋」 as five,
  which are not the same amount of speech by a factor of three.

With nothing being said there is nothing to take away, so any word claims a
free floor. Every threshold here applies only mid-answer.

### `TurnCompletion` — inside `VoiceHostAdapter.swift`

Reads the volatile transcript and moves the required silence in *both*
directions:

| Verdict | Required silence | When |
|---|---:|---|
| `continuing` | 0.8 + 0.6 = **1.4s** | ends on a connective, hesitation, or question lead-in |
| `unknown` | **0.8s** | anything else |
| `settled` | 0.8 − 0.25 = **0.55s** | a visibly finished question, ≥4 syllables |

`continuing` generalises the old three phrases to the connectives and
framing phrases a Mandarin speaker actually pauses after — 但是 然後 因為 所以
如果 就是 那個 的話 我覺得 我是說 … — plus their Latin equivalents matched as a
final word, since "also" ends in "so" and is not someone trailing off.

`settled` is new and deliberately timid. Only 嗎 呢 嘛 and terminal
punctuation qualify, and only past four syllables. 「了」「吧」「啦」 are
excluded although they look like sentence-final particles: 「我吃了飯就出門」
is ordinary, and including them would buy a quarter-second by cutting
people off. A bare 「嗎」 is a misheard syllable, not a question, which is
what the syllable floor is for.

It lives in Swift because the endpointer runs on a 50ms tick in the audio
path, and a channel hop per tick would cost more than the decision saves.

## Read back over the corpus

`SpeechTurnTests.testTheCorpusEndsWhereTheEndpointerThinksItDoes` cuts every
sentence in the corpus at every clause boundary the corpus records a pause
at, and asserts the verdict there. The table was read off the classifier and
then checked case by case, not chosen and then implemented.

The two cases that matter:

| Case | Prefix at the pause | Pause | Verdict | Wait |
|---|---|---:|---|---:|
| `short-answer-not-yet` | 等一下 | 1.02s | `continuing` | 1.4s |
| `endpoint-thinking-pause` | 我想問的是 | 1.10s | `continuing` | 1.4s |

Both used to be cut in half by the 0.8s. Both are now covered. Every other
clause boundary in the corpus pauses for 180–320ms, nowhere near any
threshold, and reads as `unknown` — the ordinary 0.8s, unchanged.
`testNoCorpusSentenceIsHeldOpenAfterItEnds` guards the expensive mistake in
the other direction: no finished sentence is given the extra 0.6s.

## The Dart settle cannot pre-empt the grace

`_settleUtterance` is the 1.5s fallback for when the VAD declines, and a
grace that the fallback fires through would not be a grace. It cannot: the
Dart timer is armed from the last *partial*, and recognition trails the voice
it heard, so the fallback fires at `lastVoice + lag + 1.5s` where the
endpointer fires at `lastVoice + 1.4s`. With `lag ≥ 0` the fallback is always
the later of the two. Shortening it, or lengthening `continuingGrace` past
1.5s, would break that ordering.

## What this does not claim

**`settled` will rarely fire in practice.** Apple's volatile results
often carry no terminal punctuation — the final 。 lands with the settled
result, after the decision has been made. So in live use the shortening
depends on 嗎/呢/嘛, which arrive as words. The `continuing` side is where
the value is; `settled` is a bounded bonus, and its 0.25s was chosen small
because it is the direction that can cut a user off.

**A lexicon is not a model.** It is wrong in ways that can be read off the
table and fixed by editing a list, which is the property being bought. It
does not generalise to a speaker whose fillers are not in it, and it does
not handle Taiwanese Hokkien at all — see
[taiwan-mandarin-voice-candidates.md](taiwan-mandarin-voice-candidates.md).

**Neither number has been measured end to end on live speech.** The corpus
is twelve read recordings, and what is checked here is that the classifier
agrees with the pauses that corpus already measured. Whether 1.4s *feels*
right is the thing to find out by talking to it, which is what the
turn-taking panel under Settings › Taking turns exists for.
