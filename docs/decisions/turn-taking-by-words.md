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

## The built-in lists are a guess; the user's are not

Every list here is an assertion about how people talk, made by someone who
is not the person talking. `TurnTakingWords` in the agent profile extends
all three from the file the user already edits — and that file is watched,
so a word added after being cut off once takes effect without a rebuild:

```json
"turnTaking": {
  "acknowledgements": ["蛤"],
  "corrections": ["先停"],
  "unfinished": ["我的意思是說"]
}
```

The first two are read by `FloorControl` at the moment of each ruling, so
they land on the next thing said. The third belongs to the native
endpointer, which cannot read Dart state on its 50ms tick, so it is pushed
across `VoiceHostApi.useUnfinishedEndings` — sent when the ears open and
again whenever the list changes, checked once per settled utterance. That is
a beat slower than the other two and appropriate: it is a setting somebody
edits after being cut off, not one that changes inside a sentence.

Matching follows whatever the built-in of the same kind does, so an addition
behaves like the words it joins rather than like a special case. The full
table is in [../features/agent-profile.md](../features/agent-profile.md).

## What a language with no lexicon gets

Every list above is an assertion about one language, so it is worth saying
plainly what happens to a language nobody has written one for.

| | Covered | Falls back to |
|---|---|---|
| Backchannel | Han, some English | speech shorter than 0.5s (below) |
| Correction | Han prefixes, English first words | nothing — needs 3 syllables like anything else |
| Continuing | Han, English final words | flat 0.8s, which is what it was before this document |
| Settled | Han particles | **terminal punctuation**, which every locale's recogniser writes |

Two things are already language-neutral: terminal punctuation, and the
syllable count — which holds for CJK and Latin and would over-count Thai or
Devanagari, where a character is not a syllable.

Nothing regresses. An unlisted language endpoints at 0.8s, exactly as
everything did before, and interrupts on three syllables, which is close to
the four characters that preceded this. The gap is **backchannels**, the
expensive one: 「うんうん」 and 「네네」 clear three syllables comfortably and
would end an answer.

### The one signal that needs no words: how long the burst ran

A backchannel is short in every language that has been studied, and a
request to take the floor is not. `VoiceActivityBox` now records where the
current burst of voice began — the gap that ends a burst is 0.35s, well
below the endpointer's, because this measures one run of speech and not one
turn — and it rides on every partial as `speechMs`.

`FloorControl.speechToInterrupt` is 0.5s, the same figure LiveKit's
`min_duration` defaults to. It is a floor under `substance` **only**:

- a **correction** lands however short it was, because being unable to stop
  the agent is the worse failure and 「不對」 is about 350 ms;
- an **acknowledgement** is ignored however long it ran;
- **substance** now needs three syllables *and* half a second of speech.

That is what stops 「うんうん」 without knowing any Japanese. It also improves
Chinese, which was not the point but is the reason to keep it: a misheard
blip that happens to transcribe as three characters no longer ends an
answer, because it never lasted long enough to be three characters.

Unmeasured is null and behaves exactly as this did before the measurement
existed, so a surface with no VAD behind it — the preview, a widget test —
loses nothing.

### The other signal that needs no words: what the speaker does next

A lexicon written by somebody else is a guess. A lexicon learned from the
person talking is not, and learning needs no language knowledge at all —
only the shape of having been cut off mid-thought: **a turn submitted, its
answer talked over, another turn straight after.**

`CutOffLedger` watches for that shape and counts what the cut-off sentence
*ended on*, at every tail length from two units to five, where a unit is one
Han character or one whole Latin word.

Detection is deliberately loose and counting is what makes it precise. A
question genuinely interrupted for a good reason looks exactly like a
cut-off once; it does not look like one three times ending on the same
words. Every shorter tail of a repeated phrase repeats with it, so they all
cross the threshold together and the longest is the real phrase —
「我想說的是」 is raised and 「的是」, which matches half the language, is
not.

It **suggests and nothing more**. The panel says `learned · 我想說的是 · cut
off 3 times — add it to turnTaking.unfinished`, and the user adds it or does
not. An app that silently rewrote how it listens to somebody would be harder
to trust than one that stays slightly wrong until it is told; and a
suggestion the user has already acted on stops being made, because the
ledger reads the profile live.

## Prosody was the obvious way to make this language-neutral. It does not work here

Every lexicon above is an assertion about one language. The standard escape
is prosody: **final lowering** — the pitch falling to the bottom of the
speaker's range as an utterance ends — is among the best-attested
near-universal turn-end cues, and it would replace half of this with
something that needs no words at all.

Measured, over the same twelve recordings, with the autocorrelation pitch
tracker already in `sidecars/tone_probe`. For every pause found by energy,
the pitch across the 300 ms before it, normalised into that speaker's own
5th-to-95th-percentile range so 0 is the bottom of their voice and 1 the
top:

| | n | Final position | Median | Slope across the window |
|---|---:|---|---:|---|
| Turn end | 12 | 0.00–0.34 | **0.06** | −5.8 … +1.2 st |
| Mid-utterance pause | 19 | 0.00–0.44 | **0.10** | −5.1 … +3.0 st |

The ranges nest, the medians are a rounding apart, and the mid-pauses sit
*lower* than the endings — the opposite of the hypothesis. Energy does
slightly better and still overlaps almost completely: 0.05–0.58 of peak at a
turn end against 0.20–0.82 at a pause.

There is a mechanism, and it is not an accident of this corpus. **Mandarin
spends F0 on lexical tone.** The pitch at any moment is mostly determined by
which of the four tones the syllable carries, and phrase-final intonation is
a small perturbation on top of that. The one prosodic cue that is supposed
to be universal is the one a tone language has already spent.

The instrument was checked before the result was believed, the same way it
was for Smart Turn. Given 300 ms from an utterance's *opening* — which is
unambiguously not the end of anything — the same measurement reports a
median position of 0.16 against 0.06 at a turn end. It sees the difference
it is built to see; it is the two populations that are not distinct.

Twelve read recordings from one speaker, and read speech is flatter than
spontaneous speech, so this is not a claim about prosodic turn-taking in
general. It is a claim about whether pitch can carry this decision here, and
it cannot. `sidecars/tone_probe/endpoint_pitch.py` is the probe.

What this leaves: the language-neutral signals worth having are not in the
pitch. They are **how long the burst of speech lasted** — a backchannel is
short in every language studied — and **what the speaker themselves does
after being cut off**, which is a signal that needs no language knowledge at
all because it comes from the person talking.

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
