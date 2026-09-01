# Pronunciation respelling

A fix for a voice that says the wrong word, without changing the voice.

## The problem

The resident TTS mispronounces a set of words badly enough that a
recogniser cannot recover them and a listener notices something is off.
Measured — 企業 renders as 奇幼, 規劃 as 窺 what, 訓練 as 碎裂, 開發 as
缺乏, 螢幕 as 實木, 瀏覽器 as 雷亮記. Across **1,791 words** — 591 written
by hand for what this agent says, then the 1,200 commonest words of the
language — **223 came back wrong, one in eight**. See
`docs/decisions/taiwan-mandarin-voice-candidates.md` for the model
comparison this sits on top of.

It is a lookup table and it has to be. The defect belongs to the **word**,
not to its characters: 頻率 is right and 頻寬 is wrong, 開始 is right and
開發 is wrong, 頁面 and 首頁 are right and 「128 頁」 is wrong. A
character-level rule would fire on the correct words too. What can be
automated is everything except the lookup — see *Growing it* below.

## What was tried instead of a table, and why it is gone

- **Pinyin annotation.** The model does not accept it. `qi1業` renders as
  七一一 — it reads the digits aloud.
- **The unquantised build.** Same model without 8-bit quantisation scores
  26/37 against the quantised 27/37. The defect is in the model, not its
  compression.
- **A different model.** VoxCPM2 is much better on isolated words (89%
  against 73%) and no better on real sentences (CER 0.087 against 0.093),
  while taking twice as long to speak, on a laptop that is also running the
  model generating those words.
- **Rendering the whole sentence Simplified.** The most promising idea,
  because the Simplified *spelling of one word* is what fixed 開發, 檔案,
  網頁, 頁 and 蔥薑蒜 when no homophone would — so perhaps the model simply
  prefers the script its training data was written in, and one
  transformation could replace the whole table. Measured over the forty
  answers: **0.0865 Simplified against 0.0732 Traditional**, both with no
  table applied, twelve sentences worse and two better. The idea is dead;
  the per-word use of it is not, and it is ranked **last** among proposals
  for a reason given under *Growing it*.

## What works

Spell the word as a different word that sounds the same. Writing 氣業 makes
the voice say qì yè, which is what 企業 is.

Every entry was verified the same way: render `這個詞是X。` with the
respelling, transcribe it, and accept only when the **original** word came
back. That the recogniser writes 企業 having been given audio synthesised
from 氣業 is the evidence — the sound was right enough for a language model
to prefer the real word.

One entry is not a homophone but a script. 開發 has no common homophone for
its second syllable, and every attempt slipped a tone; writing it
Simplified, **开发**, comes back perfect. Same trick, second door.

## What it is measured on

`corpus.py`, three corpora answering three questions.

| Corpus | What it renders | What it can say |
|---|---|---|
| `SCREEN` | 287 words, each alone in `這個詞是X。` | Finds a defect. Cannot clear one. |
| `IN_A_SENTENCE`, `AGAIN` | one and then a second natural sentence per word | Convicts. Cannot acquit. |
| `ANSWERS` | 40 whole sentences in the agent's voice | The regression the table is held to. |

Both halves of that have a name attached.

**The screen convicts things that are innocent.** 字串 came back as 自傳
every time in the carrier and is word-perfect in both sentences. 自傳 is
simply the likelier pair of characters for that sound, and the voice was
right. No entry was written for it.

**The sentences acquit things that are guilty.** 訓練 comes back perfectly
in both of its sentences, and the person this was built for reported it by
ear as wrong — which is where this round of work started. Four more —
學習, 電視, 客戶, 溝通 — were repaired in the first sentence and broken in
the second, making the same point without anyone having to be believed.

So a word earns an entry when the screen destroys it, a respelling brings
it back, and no sentence gets worse. That is the standard the original
eleven entries were held to, and this round kept it.

## The measured result

Eleven entries to **two hundred and fourteen**, over three rounds.

| | no table | 48 | 86 | 214 |
|---|---|---|---|---|
| mean character error, 40 answers | 0.0732 | 0.0487 | 0.0449 | **0.0353** |

Answers improved / unchanged / **worsened**: 7 / 33 / **0** at the first
merge, and **no sentence has regressed at any point since**. The first
column is this voice with the table emptied, so the whole of that
improvement belongs to the entries — a **52% cut** in character error on
the agent's own sentences.

The last hundred and twenty-eight entries were found and fixed by machine:
`grow_respellings.py` screened twelve hundred words, lost a hundred and
forty-one, and proposed and verified a respelling for a hundred and
thirty-one of them with nobody choosing anything.

Still broken and no spelling fixes them: **頻寬, 頻繁, 毫升, 毫米, 諮詢,
研製, 政體, 時期, 反映, 只能, 行使, 一帶, 不禁, 縣級**. Broken in the bare
carrier and correct in every sentence, so deliberately **not** in the
table: **字串, 檔名, 十五, 只要, 但是**. Dropped by a filter rather than by
a failure: **行業** (its respelling is misread inside 五金行業), **用戶**
(Taiwan says 使用者), **勢力** (its respelling is already taken).

## Growing it

Nobody hand-picks a respelling any more, and nobody using the app is
expected to. `candidates.py` proposes them, ranked, and
`grow_respellings.py` in the `lulo-tts` repository closes the loop: screen
a word, and if it does not come back, render proposals until one does, then
check the word's sentence is no worse.

```sh
.venv-ears/bin/python grow_respellings.py \
    --words words.txt --sentences sentences.json --out new_entries.json
```

The proposer ranks by two dictionaries. `pypinyin` says which characters
share a reading, tone included — that is what *same sound* means, and it is
checked rather than trusted, because the round trip is still the judge.
`jieba`'s word list gives a character frequency, and the pool is ranked by
it: a rare homophone is a new defect waiting to happen, since the voice is
no likelier to say 㰪 correctly than 規.

**The Simplified spelling of the word goes last**, and that ordering is the
one judgement in the file. It is the strongest fix — it is the same word
rather than a lookalike — and it is the one this instrument cannot check: a
recogniser writes 企業 down whether it heard qì yè or qǐ yè, so a word
rewritten in the script most of the model's training data used could shift
its reading toward the mainland standard invisibly. A homophone cannot,
because the pool is built from characters sharing a reading *including its
tone*. Ranked first — which it was, for one run — a table grown this way
would trade a defect a listener notices for one nothing here can see.

Sharing *a* reading is not sharing *the* reading, and that difference bit
once. 務 is wù and carries a literary wú, so 无 came out of the pool for it;
質 is zhì and 之 carries a rare zhì, so 之量 was proposed for 質量. Neither
sounds like the word, and the bare carrier cannot say so — 之量 is not a
word, so the recogniser writes 質量 down from a wrong sound, which is the
字串 bias pointing the other way. A candidate whose **primary** reading
matches the word's now sorts ahead of one that only shares a rare one, which
took the hand-picked answer from 45 of 86 inside the top twelve to 66.

**What this cannot do**, pinned by a test so nobody assumes otherwise: it
cannot fix a Taiwan reading. 企業 is qǐ yè in the dictionary and qì yè here,
and 氣 shares no reading with 企, so 氣業 is not in the pool at any depth —
nor is 維險 for 危險, nor 西帶 for 攜帶. The loop fixes a word the voice
**destroys**. A word the voice says with the mainland reading survives, a
recogniser writes it down happily, and only pitch or a pair of ears can see
it: that is `sidecars/tone_probe`, and it is where the first eleven entries
came from.

About two seconds a render, so a thousand words is roughly forty minutes of
screening plus a minute for each broken word. `AgentProfile.respellings` in
Settings stays what it always was: an escape hatch for one word somebody
notices, not the mechanism.

## Re-running it

The scripts that load a recogniser live in the `lulo-tts` sidecar
repository, for the reason the packages here are import-light: the quality
gate runs these tests with nothing installed.

```sh
# in ~/dev/lulo-tts, with the voice sidecar up on 46557
.venv-ears/bin/python measure_respellings.py screen    --out screen.json
.venv-ears/bin/python measure_respellings.py sentences --out before.json
.venv-ears/bin/python measure_respellings.py sentences --respell --out after.json
```

Two traps that instrument now has guards for, both hit on the way here.

**OpenCC `s2twp` converts terms, not only characters.** It rewrites 数据 to
資料, 文件 to 檔案, 权限 to 許可權, 参数 to 引數. Five words the voice said
perfectly scored as destroyed because of it. The conversion for a
measurement is `s2tw`.

**A recogniser given a carrier with no meaning picks the likelier
characters.** 計劃 coming back for 計畫 is the voice being right. The
verdict is three-way — `written`, `sounded`, `lost` — and only `lost` is a
defect.

## The two rules

**Render only.** The respelling lives between the text and the synthesiser.
It must never reach the conversation, storage, or the screen. A user who
read 氣業 in their own transcript would rightly conclude the agent cannot
spell.

**Same sound, always.** An entry that changes the sound is the voice saying
a different word, which is worse than the defect it replaces because
nothing in the text shows it. The tests enforce equal syllable counts and
that no respelling is itself a table entry.

That second rule is also what makes a table this size safe without a word
segmenter. 記錄 → 記路 fires inside 登記錄音 as well, and 登記路音 is read
aloud identically — a substitution across a word boundary costs nothing as
long as the sound is preserved. The exception is a polyphone at that
boundary: 成長 → 成掌 inside 造成長期 would say zhǎng where the sentence
needs cháng. An entry whose characters change reading with the word after
them does not belong in this table.

## Applying it

`respell` makes one left-to-right pass, taking the longest entry that
starts at each position, so nothing an entry writes is read by another one.
Rounds of `str.replace` gave the same answer while the table held eleven
words sharing no characters; at forty-eight, 檢查 and 查詢 overlap and the
result depended on dictionary order. The Dart side reaches the same
behaviour through `applyMisheardWords`, and the two agreeing is worth more
than either being clever.

The voice sidecar imports this table **once, at startup**. A word added
here reaches the user's ears when that process is next started.
