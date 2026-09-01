# Which voice says Taiwan Mandarin properly

Status: measured, not yet adopted. 2026-08-04.

## The complaint, made falsifiable

"He sometimes gets the tone a bit wrong on some nouns and some characters."

True, and impossible to act on. So: render `這個詞是X。` with a candidate
voice, send it back through Whisper, and see whether X returns. The carrier
is what makes this work — a sentence with meaning would let the recogniser
repair a mispronunciation from context, and "this word is X" gives it
grammar and no clue at all.

The resident voice, on its own reference recording:

```
這個詞是企業。 -> 这个词是奇幼
這個詞是危險。 -> 这个词是吸混
這個詞是攜帶。 -> 这个词是头戴
這個詞是品質。 -> 这个词是品机
這個詞是蝸牛。 -> 这个词是犀牛
這個詞是音樂。 -> 这个词是音卧
這個詞是成長。 -> 这个词是成整
這個詞是編譯。 -> 这个词是偏西
這個詞是結構。 -> 这个词是极口
這個詞是檸檬。 -> 这个词是鸡蒙
```

Four carrier characters perfect every time, the word under test destroyed.
This is not a subtle accent. Ten of thirty-seven probe words come out as a
different word, and 企業, 結構, 編譯 and 模型 are words this agent says
about its own work constantly.

## What was measured

Thirty-seven probes: four tone controls, nine words where Taiwan and the
mainland disagree about the reading, ten polyphones in matched pairs, six
一/不 sandhi cases, eight technical nouns. Every render written to a file;
nothing was played.

| Candidate | Words survived | RTF, probes | RTF, real sentence |
|---|---|---|---|
| Qwen3-TTS 0.6B Base 8bit (resident) | 27/37 — 73% | 0.60 | 0.60 |
| IndexTTS-1.5 (same reference audio) | 13/37 — 35% | 1.30 | — |
| **VoxCPM2 4bit, 10 steps** | **36/37 — 97%** | 2.47 | 1.78 |
| **VoxCPM2 4bit, 4 steps** | **33/37 — 89%** | 1.09 | **0.85** |

VoxCPM2 at its default step count says every one of the ten words the
resident voice destroys. Its single miss is 部署 transcribed as 部属,
which is the same sound — on pronunciation it is effectively perfect.

RTF below 1 is the bar: above it, generation cannot keep up with playback.
The probe figures are pessimistic because a six-character utterance is
mostly fixed overhead; the real-sentence column is the one that decides,
measured on a 10-second answer of the kind the agent actually gives.

## Tone, separately

"Did the word survive" is binary and hides how it failed. Reading the
transcript back as pinyin scores every syllable twice — once for the sound
and once for the tone on it:

| Candidate | Syllable sound | Tone | Right sound, wrong tone |
|---|---|---|---|
| Qwen3-TTS (resident) | 79% | 73% | 4 |
| VoxCPM2, 10 steps | 95% | 91% | 3 |
| VoxCPM2, 4 steps | 90% | 87% | 2 |
| IndexTTS-1.5 | — | — | 36 of 37 unalignable |

The last column is the surprise. The complaint was about tone, and tone
alone accounts for four errors out of thirty-seven words. The rest are not
a tone slipping — they are a different syllable entirely, which is why
Whisper writes 奇幼 and not 企業. What is heard as "slightly wrong tone" is
mostly the voice saying another word and the listener's ear repairing it
far enough to notice something is off without noticing what.

That matters for the fix: better tone modelling would not have helped. A
model that gets the syllable right is what was needed.

## The trade

VoxCPM2's `inference_timesteps` buys accuracy with time, and the two
useful settings sit on either side of the real-time line:

- **10 steps**: 97% correct, RTF 1.78 — cannot keep up with speech.
- **4 steps**: 89% correct, RTF 0.85 — keeps up, and still well clear of
  the resident voice's 73%.

At 4 steps two of the four controls fail (媽媽 came back as 爸爸), which is
a warning worth taking seriously rather than a rounding error.

## IndexTTS, and why it is out

IndexTTS-1.5 is the only candidate that accepts **pinyin annotation**:
write `qi4業` and the reading is dictated rather than guessed, which would
be a deterministic fix for exactly this defect. mlx-audio carries the
backend and the tone-digit pattern is in its text normaliser.

It scored 35%. Every utterance began with garbage — `這個詞是` came back as
`非非` or `飛飛` — which looks like a fault in how this repository drives
it rather than in the model, and it was not worth chasing: at RTF 1.30 it
cannot keep up with speech even when it is right.

Worth revisiting only if the pinyin route becomes the strategy.

The resident Qwen3-TTS does **not** accept pinyin. `qi1業` renders as
七一一 — it reads the digits.

## Then the probes were checked against real sentences, and the case collapsed

Eight sentences of the kind this agent actually speaks — forty characters
each, carrying the same failing words — rendered by both and transcribed
back:

| Candidate | Mean CER | RTF over the set |
|---|---|---|
| Qwen3-TTS (resident) | 0.093 | 0.52 |
| VoxCPM2, 4 steps | 0.087 | 1.02 |

Six tenths of a point apart. Nothing like 73% against 89%.

The probes overstate the difference, and it is worth being precise about
why, because the same trap is waiting for the next measurement. A probe is
one word inside a seven-character carrier. That is a short, contextless
utterance, and a model that predicts sound from surrounding text has
almost nothing to predict from. Given a real sentence, the resident voice
says 企業 correctly — the very word it destroys in the carrier.

So the probe measures a real weakness under the least favourable
conditions, and real speech is more favourable than that. It remains the
right instrument for ranking pronunciation, and a bad instrument for
estimating how much better a voice will sound.

The failures also differ in kind, which an average hides. The resident
voice is consistently a little wrong: 確認 as 誇引, 編譯 as 偏系, 品質 as
品級, 危險 as 一會兒. VoxCPM2 is usually cleaner and occasionally
catastrophic — one sentence in eight came back as 斜周賽開抵抗試試 where
成長最快 was asked for, a CER of 0.32 in a set averaging 0.087, and
編譯 rendered as the English "Penid". A voice that is reliably slightly
wrong may well be preferable to one that is usually right and sometimes
unintelligible, and that is a judgement about the product, not a number.

## Recommendation

**Do not swap yet.** The evidence that justified a swap does not survive
contact with real sentences: a six-tenths-of-a-point CER improvement does
not pay for doubling the time to speak, and this machine also has Gemma on
it. Every RTF here was measured with the TTS alone; in use it shares an M1
Pro with the model generating the words it is about to say, so 1.02 is
optimistic and 0.52 is the margin that makes the current voice feel
immediate.

### Quantisation is not the cause — tested and refused

The cheapest possible fix would have been the same model without the
8-bit quantisation: same voice, same integration, no product risk.

`Qwen3-TTS-12Hz-0.6B-Base-bf16` scores **26/37 — 70%**, against the 8-bit
build's 27/37. That is noise, not an improvement; the two lose slightly
different words (bf16 says 企業 correctly and loses 垃圾 and 媽媽, which
the 8-bit build gets right) and the same number overall.

So the mispronunciation is in the model, not in its compression. Nothing
is to be gained by shipping the larger weights, and the possibility is now
closed rather than left hanging as an untested hope.

(Its RTF of 2.14 is not comparable to the 8-bit 0.60: this run went
through mlx-audio cold while the baseline is a warm resident server. Speed
was not what the experiment was asking.)

### What did fix it: spell the word as a different word

Every avenue above assumed the answer was a better model. It was not.

Writing 氣業 makes the voice say qì yè, which is what 企業 is. The
recogniser, given audio synthesised from 氣業, writes back 企業 — the sound
was right enough for a language model to prefer the real word, which is the
evidence that it was right.

Ten of the eleven measured failures are fixed this way. On whole sentences:

| Sentence | Before | After |
|---|---|---|
| 危險的操作… | CER 0.214 | 0.111 |
| 品質跟速度… | 0.077 | 0.038 |
| 成長最快的… | 0.074 | 0.019 |
| 好的，我幫你確認… | 0.122 | 0.122 |

The last row is the control and the useful one: 結構 was already correct in
that sentence, and the remaining error was 確認, absent from the table at
the time. The substitution changes what it was measured on and nothing
else.

Shipped as `sidecars/pronunciation`, applied between the text and the
synthesiser and nowhere else — the conversation, the stored turn and the
screen all keep the real spelling. No model change, no speed cost, and the
table records the defect each entry fixes so it can be deleted when a
future model no longer needs it.

### The table the user can reach

The eleven entries above are the ones measured here. They are not the ones
somebody will hit next, and adding to them meant editing a Python file in
this repository and restarting a sidecar — while the mirror-image repair for
the *recogniser*, `AgentProfile.misheard`, has been editable in Settings and
live on the next turn all along. That asymmetry was the actual complaint the
next time a word came out wrong.

`AgentProfile.respellings` closes it. Same shape of control, in the same
section of the same sheet, applied in `PigeonVoiceService.speak` — the single
place text leaves for the voice, and deliberately the last thing that happens
to a sentence. The sidecar's built-in table stays where it is as the floor;
the user's runs first, so teaching a word overrides the shipped entry for it
rather than fighting it.

Two things a reader should know before extending this. The substitution runs
on `applyMisheardWords` rather than on a second implementation, because it is
the same problem — longest rule first, nothing one rule writes read by the
next, graphemes not code units — and every one of those properties is already
pinned by a test there. And **"same sound, always" is not enforceable in
code**: an entry that changes the sound is the voice saying a different word,
which is worse than the defect it replaces because it is invisible in text.
`sidecars/tone_probe` is how an entry gets verified; the editor cannot do it,
so the note under the field says what the field is for and the responsibility
stays with whoever types in it.

### What the evidence does support

**Listen before deciding anything else.** Naturalness, pacing, and whether
it still sounds like the same person are in none of these numbers, and they
are most of what the complaint was about. The measurements have gone as far
as they usefully can without an ear. Thirty A/B word pairs and sixteen
sentence pairs were rendered for that and have since been deleted;
`~/dev/lulo-tts/render_probes.py` and `sentence_run.py` make them again
while the candidate models stay cached.

The respelling table makes a swap less urgent rather than unnecessary: it
fixes the words it was measured against, and does nothing for the next word
nobody has hit yet.

If a swap does happen later, two things are unresolved: VoxCPM2 emits
48 kHz against the resident 24 kHz, and its occasional catastrophic
sentence needs a bound before it is allowed to speak to a user.

## What is not known

- **Intelligibility is not accent.** This measures whether a word survives,
  not whether it was said the Taiwan way. 企業 said as qǐ yè is still 企業
  to Whisper. The tone classifier in `sidecars/tone_probe` exists for that
  and is not yet trustworthy enough to quote — its controls scored 2/4.
- **Nobody has listened to the Mandarin pairs.** Naturalness, pacing and
  whether it still sounds like the same person are not in any of these
  numbers, and the thirty A/B renders they would be judged from have been
  deleted. They are reproducible from `~/dev/lulo-tts/render_probes.py`
  while the candidate models stay cached; the raw per-probe results are
  kept in
  [`../../benchmarks/voice_eval/evidence/taiwan-mandarin-voice-candidates/`](../../benchmarks/voice_eval/evidence/taiwan-mandarin-voice-candidates/).

### Taiwanese Hokkien: judged, and it does not work

VoxCPM2 lists nine Chinese dialects including 閩南話, and four Taiwanese
sentences written in Han characters were rendered to find out whether that
was real. A Mandarin recogniser is no help here and none of the measurements
in this document apply, so it needed a speaker.

**2026-08-04, judged by ear: bad.** That closes the one open question that
could have outweighed the Mandarin result — VoxCPM2 being the only candidate
with any route to Hokkien was worth more than 0.6 percentage points of CER,
and it turns out not to have the route.

Not measured further, because there is nothing to measure: a listener who
speaks the language said it does not work, and no CER over a Mandarin
recogniser would have been able to say otherwise.

## Rejected without testing

- **Cloud voices** (ElevenLabs, Azure, Google, MiniMax). Azure has real
  zh-TW voices and Hokkien, and every one of them means posting the user's
  conversation to a server. `BootstrapConfig.localOnly` is a promise this
  product makes; a better accent is not worth breaking it.
- **Kokoro** — cached and free to try, but it does not clone a voice, so
  adopting it means abandoning ryan.

## The table grew from eleven words to forty-eight, 2026-08-30

The complaint that reopened this: 「規劃、訓練這兩個詞 agent 講話都會歪嘴」.
Both are destroyed — 規劃 renders as 窺 what, 訓練 as 碎裂 — and neither was
in the eleven-word table, because that table was built from the
thirty-seven probes above and those two are not in them.

So the screen was widened to **287 words** of what the agent actually says,
carried in `sidecars/pronunciation/corpus.py`. **45 came back wrong.** Every
one that survived a second look got a respelling, verified the same way as
the original eleven; thirty-seven of them shipped.

| | before | after |
|---|---|---|
| mean character error, 40 whole answers | 0.0732 | **0.0487** |
| answers improved / unchanged / worsened | | **7 / 33 / 0** |

The *before* column already has the original eleven applied, so that is what
the new entries are worth on their own.

Three things this round established that the first one could not.

**The carrier convicts the innocent.** 字串 came back as 自傳 in the carrier
every single time and is word-perfect in two natural sentences. 自傳 is
simply the likelier pair of characters for that sound. It got no entry, and
a table built on the carrier alone would have had one.

**The sentence acquits the guilty.** 訓練 comes back perfectly in both of
its sentences, and a human reported it by ear as wrong — which is how this
started. 學習, 電視, 客戶 and 溝通 were each repaired by the first sentence
and destroyed by the second. A recogniser with context is a generous judge,
so the carrier is what finds a defect and the sentences are what stop a fix
making anything worse.

**The scorer was flattering the hypothesis.** Five words — 數據, 文件, 權限,
參數, 計算 — scored as destroyed and were perfect. OpenCC `s2twp` converts
*terms* as well as characters, rewriting 数据 to 資料 and 权限 to 許可權, so
the measurement was marking the voice down for the recogniser's own
post-processing. Measurements here use `s2tw`.

One entry is not a homophone. 開發 has no common homophone for fā and every
attempt slipped a tone; **开发**, the Simplified spelling, comes back
perfect. The model has a second door, and it is worth remembering before
declaring a word unfixable.

None of this changes the recommendation above — the voice is still
Qwen3-TTS 0.6B Base 8bit, and VoxCPM2 is still not worth twice the time.

### The second round, and the rule that does not exist

A second screen of 304 more words lost another 42, and then a
frequency-ranked screen of the 1,200 commonest words of the language lost
141 more. **1,791 words screened, 223 broken — one word in eight.** The
table is **214 entries** and the forty answers sit at **0.0353**, from
0.0732 with the table emptied: a 52% cut, none of it borrowed from a
different model.

That ratio is the uncomfortable part, and it is the honest answer to "does
this generalise": *not by itself*. So the obvious question was whether one
rule could replace the table, and it was measured rather than argued.

**It cannot, and here is why.** The defect is a property of the word, not
of its characters. 頻率 is correct and 頻繁 and 頻寬 are not. 開始 is
correct and 開發 is not. 頁面 and 首頁 are correct and 「128 頁」 is not. A
character-level rule fires on the correct words as well, and a table entry
is the only unit narrow enough.

**The one general rule that looked real, and died.** Simplified spellings
fixed 開發, 檔案, 網頁, 頁 and 蔥薑蒜 where no homophone would, which
suggested the model simply prefers the script most of its training data was
written in — and that rendering every sentence Simplified would replace the
whole table with one call to OpenCC. Measured over the forty answers with
the table emptied on both sides: **0.0865 Simplified against 0.0732
Traditional**, twelve sentences worse and two better. The per-word use of
the trick stays; the sentence-wide version is dead.

Whether a Simplified spelling also drags a *reading* toward the mainland
standard is a question this measurement cannot answer, and it is worth being
explicit about: thirteen known-divergent words came back correct under a
Simplified spelling, but a recogniser writes 企業 down whether it heard qì yè
or qǐ yè, so that says the word survived and not which reading was spoken.
The instrument for that is `sidecars/tone_probe`, which tracks pitch and is
comparative rather than calibrated. Until somebody runs it, the proposer
ranks the Simplified spelling **last** and reaches it only when no homophone
works — a homophone is tone-safe by construction, because the pool is built
from characters sharing a reading including its tone. Ranked first, it would
have traded a defect a listener notices for one the measurement is blind to.

### So the loop was automated instead

`sidecars/pronunciation/candidates.py` proposes respellings, ranked by
`pypinyin` for the reading and `jieba`'s word list for how common a
character is, with the word's own Simplified spelling first.
`~/dev/lulo-tts/grow_respellings.py` closes the loop: screen a word, render
proposals until one brings it back, then check its sentence is no worse.
The proposer reaches 72 of the 86 hand-picked answers inside its top fifty,
and it does not need to find the same one — three to five usually pass.

That is what makes the ratio survivable, and it is not a plan — the last
**128 entries were found and fixed with nobody choosing anything**. The
loop screened twelve hundred words in about three hours, lost 141, and
verified a respelling for 131 of them, each against a sentence as well as
the carrier. Growing the table is machine time now, and it can be re-run
from scratch the day the voice model changes, which is exactly when a table
of hand-picked substitutions would otherwise become a liability.

Three guards came out of running it, each after the loop proposed something
wrong:

**Sharing *a* reading is not sharing *the* reading.** 務 carries a literary
wú beside its ordinary wù, so 无 was proposed for 業務; 之 carries a rare
zhì, so 之量 was proposed for 質量. Neither sounds like the word — and the
bare carrier cannot say so, because 之量 is not a word and the recogniser
writes 質量 down from a wrong sound. That is the 字串 bias pointing the
other way. Ranking a candidate whose *primary* reading matches took the
hand-picked answer from 45 of 86 inside the top twelve to 66.

**A respelling that is safe in a word can be wrong inside a longer one.**
行業 → 形業 also fires inside 五金行業 and 分行業, where 行 is háng. Every
other entry, old and new, was checked against 335,000 dictionary words and
is clean; the check is now a test and a merge filter.

**A frequency list from a mainland dictionary carries mainland words.** 用戶
scored as broken and Taiwan says 使用者, so the "defect" was the
recogniser's own term conversion. Dropped by `s2twp(tw2s(word)) != word`.

The residue after three rounds: fourteen words are broken and no spelling
fixes them (**頻寬, 頻繁, 毫升, 毫米, 諮詢, 研製, 政體, 時期, 反映, 只能,
行使, 一帶, 不禁, 縣級**). Five are broken in the bare carrier and correct
in every sentence, and were deliberately left out (**字串, 檔名, 十五, 只要,
但是**).

And the boundary worth writing down for whoever picks this up: the loop
fixes a word the voice **destroys**, and cannot touch a word the voice says
with the mainland reading. 企業 is qǐ yè in the dictionary and qì yè here,
and 氣 shares no reading with 企, so 氣業 is not in the candidate pool at any
depth — nor is 維險, nor 西帶. Those came from the tone probe and a pair of
ears, and the next ones will have to as well.
