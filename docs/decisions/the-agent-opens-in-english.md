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

## Known gaps

- **The profile editor shows a Chinese default tone.** `AgentPersonality.tone`
  defaults to 「親近但不裝熟」 and `AgentProfileSettings` renders it in a text
  field, so an English-first user meets a Chinese value there. The composer
  already *excludes* the tone when it equals the built-in default, so the
  field is showing an instruction that is not in force — which is misleading
  in both languages. The fix is in the editor, not the default.
- **`sectionDesktop` is a duplicated key** in both `app_en.arb` and
  `app_zh.arb`, with different values; the second silently wins for both
  sections that use it. Pre-existing, unrelated to language, found while
  editing the files.
- **The always-listening path in English has not been re-measured** since it
  got a locale it could be told. Its published figure, 13.4% heard CER, was
  obtained with the recogniser pinned to the machine's language.
