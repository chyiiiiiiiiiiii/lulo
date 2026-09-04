# The agent opens in English

Lulo now starts in English and Chinese is a switch in Settings. This is not a
retreat from Chinese — the Chinese work is what made the asymmetry visible —
and it changes less code than it sounds like, because most of the app was
already bilingual. What it changes is the one decision that had to be made
before anybody has spoken: **which language the recogniser is opened on.**

## Why English is the better default today

Three measurements, run on this machine before anything was written.

### The voice reads English word-perfect and needs no table

Twelve sentences in the shape this agent actually answers in, rendered by the
resident synthesiser at `lang: "en"` and read back through
`whisper-large-v3-turbo`:

| | |
|---|---|
| WER | **0.054** |
| Word-perfect | **10 / 12** |
| Time to first audio | 0.31–0.81 s |
| Render speed | RTF ~0.65 — the voice outruns itself |

Every one of the six errors is a numeral convention and not a mispronounced
word: `twenty past three` written back as `20 past 3`, `three point
forty-four` as `3.44`. **Zero pronunciation defects.**

Set that against the Chinese side, which is documented in
[taiwan-mandarin-voice-candidates.md](taiwan-mandarin-voice-candidates.md):
1,791 words screened, **223 broken — one word in eight**, and 214 respellings
in `sidecars/pronunciation` written to repair them. The reference recording
the voice is cloned from is *Chinese*, which is what made this worth
measuring rather than assuming — and it turns out to carry English cleanly
anyway.

That is the whole argument. The English half of this product needs no
pronunciation table, no screening loop, and no maintenance the day the voice
model changes.

### The batch recogniser was already listening in both

The hold key is the default way in, and behind it the sidecar pins
`language="zh"`. Over the sixteen real English recordings in
`benchmarks/voice_eval/corpus/en-spoken-v1.json`:

| Setting | WER | Word-perfect |
|---|---|---|
| Breeze, `language="zh"` (what ships) | 0.173 | 7/16 |
| Breeze, `language="en"` | **0.173** | 7/16 |
| whisper-large-v3-turbo, `language="en"` | 0.186 | 5/16 |

Identical, character for character. Breeze auto-detects and the flag reaches
nothing. **So the sidecar was not changed** — a language switch there would
have been a change with a measurement of zero behind it.

### The Chinese prompt helps English, which was the opposite of the guess

The sidecar feeds Whisper a Chinese `held_prompt` — written as fully
punctuated spoken Chinese, because Whisper continues the prompt's style. The
obvious worry is that a Chinese sentence in front of English audio drags the
transcript sideways. Measured over the same sixteen:

| Initial prompt | WER | Word-perfect |
|---|---|---|
| The Chinese one, as it ships | **0.115** | 9/16 |
| None | 0.173 | 7/16 |
| An English one carrying the same terms | 0.122 | 9/16 |

The prompt's *terms* are doing the work, not its language, and the Chinese
one is not a handicap — it is the best of the three. **So the sidecar was not
changed here either.** Two changes were planned for it and both were deleted
by evidence.

### English is not cheaper, and that is worth writing down

The obvious next claim is that English is also faster, because Han costs
several tokens a character where English costs a fraction of one. Measured
through the app's own estimator — `estimatedTokenCount`'s rule, which
deliberately errs high — on the same default profile:

| | System instruction | Turn half |
|---|---:|---:|
| English, spoken | 1053 chars, ~352 tokens | ~17 |
| Chinese, spoken | 325 chars, ~295 tokens | ~15 |

The English stable half is **longer**, not shorter: the same instructions take
three times the characters to say. So there is no prompt-cost argument for
English, in either direction that matters — the stable half is prefilled once
per conversation and the turn halves are within two tokens of each other.

The latency case for English is the one already measured at the other end: the
voice renders at RTF 0.65 with first audio in 0.31–0.81 s, and it needs no
respelling pass to be intelligible. Not the prompt.

## What English actually gets wrong

Not pronunciation, and not grammar. Product names:

```
LiteRT      → light RT
Gemma       → German
MLX         → NLOX
Dart test   → Dark text
Xcode       → xcode
Swift tests → sweep test
```

These are the same failures `docs/features/voice.md` already records for
Chinese code-switching, and the app already has the answer: `AgentProfile.
misheard`, taught once by the user, applied to every transcript afterwards.

**They are deliberately not seeded.** A built-in `German → Gemma` rule would
corrupt any sentence genuinely about German, and every one of these
mishearings is a correctly spelled ordinary word — which is exactly why
nothing downstream can detect them and why the user, who knows what they
said, is the only one who can teach the correction.

## The English preface, measured for the first time

`agent_prompt_composer.dart` carries a comment on its English branch saying
*"Mirrors the Chinese, which is what was probed; this side has not been."*
That was defensible while English was the fallback. It stopped being
defensible the day the agent started opening in English, so
`EnglishPrefaceProbeTests` now asks the English text the three questions the
Chinese one earned the hard way. Against the real gemma-4-E4B:

| | Result |
|---|---|
| Name survives sampling (5 seeds, t=0.7) | **Lulo 4/5** |
| Capability boundary (3 seeds, "find me a quiet café") | **clean 3/3** |
| Answer spread across the five-question gradient | 1, 2, 3, 3–4 sentences |

**The persona is at the bar, not above it.** Seed 5 answered "My name is
Gemma 4." The Chinese side has the same failure mode and the same repair —
one specific sentence in one specific slot — and English carries that
sentence and still slips one time in five. It passes the ≥4/5 bar the Chinese
probe set, and it is the first thing to look at if the identity ever feels
loose.

**The boundary line works.** All three replies said plainly that it has no
location and no live business data, invented no shop, and promised no search.
That line exists because without it the model invented three cafés and offered
to go and look them up; the English rendering of it holds.

**Length is granular differently, and one attempt to fix it failed.** Same
model, same seed, same five questions in both languages:

| | Sentences | Characters |
|---|---|---|
| English | 1, 2, 3, 3, 3 | 16, 39, 185, 367, 428 |
| Chinese | 1, 2, 3, 4, 5 | 20, 15, 71, 142, 213 |

Chinese expands by adding sentences; English caps at three and expands by
making each one twice as long — under a block whose last line asks for short
sentences *because they are being spoken aloud*. The spoken duration is
comparable (428 English characters is about the 172 Chinese characters that
`answer-length` measures at twenty-seven seconds), so this is granularity, not
verbosity.

A candidate rewording was probed, saying what expanding means — "use more
sentences rather than longer ones — seven or eight short ones beat three long
ones". Three seeds each: **shipped 3, 3, 4 sentences; candidate 4, 3, 3.**
Nothing moved, and the persona held 3/3 in both. So the line was **not
changed**, and the condition is kept in the probe so the next person does not
spend the same afternoon on the same idea. Running three seeds is also what
showed the shipped preface already reaches four sentences sometimes — the
single-seed reading that started this was narrower than the truth.

One instrument defect is worth recording with it: the first spread run capped
output at 320 tokens and the two heaviest answers came back cut mid-word,
`"twenty grams s"`. Their sentence counts were the cap's, and the assertion
passed on a number the harness had invented. The probe now refuses to count an
answer that does not end in sentence punctuation.

## Where the decision lives

`AppSettings.conversationLanguage`, an `AgentLanguage` in `agent_core`,
defaulting to `english`.

**Why not `AgentIdentity.locale`,** which has carried a doc comment reserving
it for exactly this since it was written. Because it already says `zh-TW` in
every `agent_profile.json` on disk. Flipping its default would have moved
nobody who already uses the app — which is everybody who uses the app. A key
that has never been written is the only kind whose absence can mean "English".

The old field keeps its job of being unread, with its comment updated to point
here.

## How it reaches the microphone

```
AppSettings.conversationLanguage        the user's choice
  → AppComposition.conversationLanguage a notifier, like answerStyle beside it
  → ConversationView                    a callback, read at the moment
  → VoiceConversationController         _pushRecognitionLocale()
  → VoiceHostApi.useRecognitionLocale   pigeon, before startListening
  → VoiceHostAdapter.chosenLocale       stored, read at the next begin()
  → RecognitionLocale.resolve           against what the platform can speak
```

Four things about that chain are load-bearing.

**Before `startListening`, not after.** The transcriber's locale is fixed when
the session opens. A locale that arrives late sets the language of the session
*after* this one, and the user has to say their first sentence twice.

**Not re-sent while unchanged**, on the same rule as the vocabulary and the
unfinished endings beside it: this replaces what the recogniser is holding,
and it is usually holding the right answer already.

**The machine's own languages are the floor, not the roof.** The choice used
to be made natively from `Locale.preferredLanguages` alone, which is why an
English agent on a Chinese Mac could not be expressed at all. That fallback
stays, underneath the app's choice, for the two cases where the choice cannot
be served: a microphone opened by a path that never went through the setting,
and a locale the platform has no model for. The wrong language beats no ears,
and the log says which one it got.

**The language subtag decides.** A tag is written `zh-TW`, `zh-Hant-TW`,
`zh_Hant`, `en-GB`; none of those differences pick a different transcription
model. Both sides read the first subtag and nothing else, and both sides are
tested on it — `RecognitionLocaleTests` natively, `AgentLanguage.ofLocale` in
`agent_core`.

## What deliberately did not change

- **The prompt.** `composeAgentPrompt` takes the language from the question
  itself and always has, because a small model answers in the language it was
  instructed in. A Chinese question typed into an English agent still gets a
  Chinese answer, and that is correct rather than a leak.
- **The synthesiser's language**, which is chosen per answer from the script
  of the text. A Chinese quotation inside an English answer is still read as
  Chinese.
- **Turn-taking.** `FloorControl` and `TurnCompletion` carry English
  backchannels, corrections and connectives already, and the burst-duration
  signal underneath both needs no language at all.
- **The respellings**, which are keyed on Chinese words and match nothing in
  an English sentence.
- **The UI's own language**, which follows the Mac. These are two axes on
  purpose: a Chinese-speaking user can run an English agent and read Chinese
  buttons, and that combination is the one this change exists to serve.

## What the first pass left, and what happened to it

Four things were written down as gaps when the default moved. Three are
closed; the list is kept because two of them closed by being **corrected**
rather than built, and that is the more useful record.

**The profile editor showed a Chinese default tone — fixed.**
`AgentPersonality.tone` defaults to 「親近但不裝熟」 and the editor rendered it
in the field, so an English-first user met a Chinese value there. The deeper
problem was true in both languages: `composeAgentPrompt` *excludes* the tone
while it equals the built-in one, because the core identity block already
states it in the language of the question — so the field was showing an
instruction that was not in force. It is empty now while it is inherited, and
the hint names what the built-in tone is. Typing in it still makes it yours,
which is pinned by its own test. The English hint no longer offers a Chinese
example.

**The always-listening figure did not need re-measuring — the claim did.**
This document first said 13.4% heard CER "was obtained with the recogniser
pinned to the machine's language". That was wrong.
`FullDuplexCorpusProbeTests` opens the transcriber on the *corpus's* locale,
so the number was always measured with English set correctly. What was broken
was narrower and invisible to that probe: a **live** session on a Chinese Mac
never reached that recogniser, because `begin()` took the machine's language.
The number does not improve; it becomes reachable. Which is also why the hold
key stays the default door at 3.8%, and the always-listening path stays behind
its own switch, off.

**The settings text had gone stale — fixed.** `hearingDuplexNote` told the
user the recogniser "uses the first of your preferred languages", which
stopped being true the moment the language became a setting. A user-facing
sentence describing behaviour that no longer exists is worse than no sentence.

**Product names are still what English gets wrong, and the app now says
where the cure is.** Still not seeded, for the reason above. What changed is
discoverability: the hold-key note names the actual mishearings — `LiteRT` as
"light RT", `Gemma` as "German", `Dart test` as "Dark text" — and points at
the list where one correction, taught once, holds for every sentence after. A
cure nobody can find is indistinguishable from no cure.

## Still open

- **`sectionDesktop` is a duplicated key** in both `app_en.arb` and
  `app_zh.arb`, with different values; the second silently wins for both
  sections that use it. Pre-existing, unrelated to language, found while
  editing the files.
- **English on the always-listening path is 13.4% heard CER** and nothing here
  moves it. The recogniser is the platform's, the vocabulary bias has twice
  been measured changing nothing, and the errors are ordinary words. The
  product answer stands: the better door is the default one.
