# The answer's length should follow the question

Every answer the app gives is the same length. The instruction says 「回答控制
在三句話以內」 — a ceiling — and the model treats it as a target: four
questions of wildly different weight came back in exactly three sentences
each, the third of them padding. 「使用前最好還是先了解相關的劑量和補充說明
書喔」 answers nothing; it fills the third slot.

What is wanted is one sentence where one will do and eight where eight are
needed.

## Why the existing evidence could not settle it

`_zhSpokenLength`'s own comment records the measurement that put the sentence
budget there: asked five conversational questions with `concise` spelled out
only as 簡潔, the model answered in 172 characters on average — twenty-seven
seconds of Mandarin — against 64 with a sentence budget.

That comparison is real and still stands. It just answers a different
question. It compared *a budget* against *no budget* and scored the **mean**
length, and the mean says nothing about whether the length follows the
question. A model that answers everything in three sentences and one that
answers everything in eight both have a defensible mean. The defect is that
the spread is zero.

So what is measured here is the **spread** and the shortest answer, over five
questions chosen for a deliberate gradient of weight — from one a single
sentence answers completely (「早安」) to one that cannot be answered well in
fewer than several (「幫我比較跑步和游泳對膝蓋的影響，還有各自適合什麼人」).

## What was compared

The two candidates are shapes taken from products that run this in
production, not invented here:

- **Deepgram's** voice agent guide specifies "1-2 sentences (under 120
  characters typically, **max 300 for complex information**)" — a typical
  value and a raised ceiling, both numbered.
- **ElevenLabs'** is "under 3 sentences **unless the user asks for details**"
  — a ceiling with an escape.

Both were written for frontier models. This one calls a registered tool 0
times out of 5 under this same preface, so the shape may transfer and the
wording may not — which is the reason for measuring rather than adopting.

| variant | the length line |
|---|---|
| **A** (today) | 回答控制在三句話以內；講完核心就停，細節等使用者追問再說。 |
| **B** | 多數問題一到三句就夠；需要步驟、比較或說明原因時可以到七八句。講完就停，不要為了湊長度補話。 |
| **C** | 回答控制在三句話以內，除非使用者要細節或問題本身需要。 |

Everything else in the preface is held identical, including 「回答長度：簡潔」
further down — it is what the app really sends, and removing it would measure
a prompt nobody uses.

## Single turn: B, clearly

Characters per answer, one fresh conversation per question, same seed per
question across variants:

| | 名字 | 早安 | 暖身 | 肌酸 | 比較膝蓋 | longest/shortest |
|---|---|---|---|---|---|---|
| **A** | 24 | 13 | 29 | 52 | 89 | 6× |
| **B** | 20 | 14 | **61** | **118** | **158** | **11×** |
| **C** | 43 | 23 | 45 | 49 | 72 | **3×** |

**B does what was asked.** The trivial questions stay as short as they are
today — 14 characters for 「早安」 — and the heavy ones actually expand, to
nearly twice A's longest. Read by eye, what B adds is substance rather than
padding: that creatine's early weight gain is water in the muscle, and to ask
a doctor first.

**C is worse than A, not merely no better.** It compressed the range from 6×
to 3× by making the short answers *longer* (24→43, 13→23) and the long one
*shorter* (89→72) — the opposite of the intent, in both directions at once.

## C also broke the persona, which nothing predicted

Under C, asked its name, the model answered:

> 我叫 **Gemma 4**。我是由 Google DeepMind 開發的。很高興為您服務。

A and B both answer 「我是 Lulo」. Same preface, same question, same seed —
the only difference is one line about length.

An escape clause on the length rule loosened the identity block three
sections above it. That is not something reading the prompt as logic would
predict, and it is the reason a 4B model's preface has to be measured as a
whole rather than edited a line at a time. Anyone adding an "unless" to this
preface in future should expect it to reach further than the sentence it is
in.

## In one conversation: B holds, A collapses

The same five questions down one conversation, which is how the app is used:

| | 名字 | 早安 | 暖身 | 肌酸 | 比較膝蓋 | longest/shortest |
|---|---|---|---|---|---|---|
| **A** | 28 | 16 | 34 | 45 | **48** | **3×** |
| **B** | 19 | 15 | 61 | 85 | **201** | **13×** |
| **C** | 29 | 25 | 40 | 54 | 55 | **2×** |

**A is flattened by its own history.** Its spread halves, 6× to 3×, and the
heaviest question comes back *shorter in conversation than asked alone* — 48
characters against 89. Nothing about the question changed; what changed is
that four shorter answers now precede it in the KV cache. That is the
screenshot, and it says the defect is not only the instruction: the model
copies the shape of what it has already said.

**B is not flattened.** Its spread widens slightly, 11× to 13×, and the
heaviest question grows to 201 characters over six sentences — the longest
answer in the whole experiment, in the condition that was supposed to
suppress it.

The reason is visible in the wording. B names its triggers as words that
appear in the question — 「需要步驟、**比較**或說明原因時」 — and question five
literally asks for a 比較. That gives the model a rule it can evaluate per
question, where a bare ceiling only leaves it a habit to imitate.

## What was adopted

B, for `concise` and `balanced`, in both languages. `detailed` already had no
number and is unchanged.

## What is not settled

The screenshot that started this shows four answers of **exactly three
sentences each**. The single-turn probe shows A spreading 13 to 89
characters. Both cannot be caused by the instruction.

The difference is that a real conversation carries the model's own previous
answers in its KV cache. The suspicion is that it copies their shape — the
second answer is three sentences because the first one was, not because the
question asked for three. If that is what is happening, a better instruction
fixes less than these numbers suggest.

That suspicion was the reason for the multi-turn run above, and it was
right. Both probes are checked in and skipped without
`REAL_GEMMA_MODEL_PATH`; re-run both if the preface changes, because the
single-turn numbers alone would have understated how bad A is and how well B
holds.

## The split that was nearly built, and the objection that stopped it

The plan after adopting B was to cap spoken answers and let typed ones run.
The arithmetic looked conclusive: B answers the heaviest question in 201
characters, and 172 characters is already recorded in this repository as
twenty-seven seconds of Mandarin, next to the words "nobody in a conversation
talks for twenty-seven seconds". It read like re-creating, for voice, the
exact failure the sentence budget was built to stop.

It was wrong twice, and the objection that stopped it was one sentence: *some
questions genuinely need several sentences to explain, and a cap truncates
them.*

**The guidance was cited out of its context.** Deepgram, NVIDIA and
ElevenLabs all cap a spoken turn at one to three sentences, and every one of
those documents is about a **transactional** voice agent — appointment
scheduling, order lookup, an alert bot. Their users do not ask 「肌酸怎麼吃？
有什麼副作用？」. Generalising "a booking bot should be brief" into "speech
should be brief" is the whole of the error.

**And this app has something those do not: working barge-in.** `FloorControl`
is measured and 「不對」 stops an answer at any length. For a phone IVR a long
answer is unrecoverable; here it is one word away from over.

## What actually hurts a spoken answer

Not the length. The opening.

Of the three long answers B produced, two led with the answer and the longest
did not:

| question | first sentence | |
|---|---|---|
| 跑步前要暖身嗎？ | 「跑步前暖身是蠻建議的。」 | the answer |
| 肌酸怎麼吃？ | 「肌酸通常是每日服用，建議您按照包裝上的建議量來吃。」 | the answer |
| 比較跑步和游泳對膝蓋 | 「跑步和游泳對膝蓋的影響是不同的。」 | **fourteen characters that say nothing** |

Thirty seconds is fine if the first five gave you the answer, because the
rest is optional and interruptible. Five seconds of throat-clearing is not,
because speech cannot be skimmed past.

The preface already says 「先回答核心」. It holds for the two easier questions
and fails on the hardest one — the model preambles *more* as the question
gets harder, which is exactly when leading with the answer matters most.

So the fix is to the opening, not the length, and it is the same rule for
both channels. Capping speech would have traded a truncated answer for a
preamble that is still there.

Measured over five questions built to provoke one — comparisons, choices and
why-questions, down one conversation. First sentences:

| | 「先回答核心」 (today) | 「第一句就要是答案本身」 |
|---|---|---|
| 比較跑步和游泳 | 跑步和游泳對膝蓋的影響**不一樣**。 | 跑步對膝蓋的衝擊力較大，需要膝蓋狀況良好的人。 |
| 為什麼膝蓋痛 | 原因比較**多樣化**。 | 很多時候是因為跑步姿勢或步態上的問題。 |
| 跑步機還是戶外 | 這**取決於**你的目標和環境。 | 這取決於你更在意什麼樣的訓練體驗。 |
| 肌酸 vs 乳清 | 是兩種**功能不同**的補充品。 | 肌酸是幫助肌肉儲存能量，讓你在高強度訓練時能多做幾次重訓。 |
| 減脂期訓練 | 重點是結合有氧和阻力訓練。 | 重點是保持高強度的燃燒，同時避免讓肌肉流失。 |

**One in five became four in five.** The old openings all restate the
question — 「不一樣」, 「多樣化」, 「取決於」 — which is the model buying time
in a medium where time cannot be bought back.

The one that did not move is the treadmill-or-outdoors question, and it is
arguably right not to: there is no objectively correct choice, the answer
does name the trade-off immediately afterwards, and it closes with 「建議先選
跑步機」. A hedge on a genuinely preference-shaped question is not a preamble.

Nothing else moved. The persona held, the lengths still followed the
questions, and the answers stayed substantive — checked against the whole
text, not only the openings, because an escape clause on the *length* line
was already found to reach three sections up and change the model's name.

The English wording follows the Chinese and **has not been measured**.

## The other half: spoken is not typed

The industry guidance found while looking for these shapes is unanimous and
points the *opposite* way from what this document wants — Deepgram says "one
or two sentences per turn", NVIDIA says 1-3, ElevenLabs says under 3 —
because "long responses increase time-to-first-word and get interrupted".

They are right, for voice. A twenty-sentence answer read by TTS is three
minutes with no way to skim and no way to interrupt without barging.

`_zhSpokenLength` is used for both typed and spoken turns, and that is the
real error underneath this one. The length rule should differ by how the
question arrived, not because a voice user deserves less but because a voice
user cannot skim.


## The first-sentence line was later measured killing tool calls, and fell

Written 2026-08-16, when the typed channel was being built. The tool probe
— by then counting executions rather than reading the reply — measured the
clock tool under the preface actually shipping, and it had gone from 5/5
to **0/5 called**. Ablated one line at a time against the real model:
reverting 「第一句就要是答案本身」 restored 5/5; reverting the length line
restored nothing. A model told the first sentence must *be* the answer
cannot stop to call a tool first — the call is not an answer sentence.

The table above says the active ingredient was never the absolutism: it
was **naming the banned preambles**. So the line shipping now is
「先回答核心；不要用「這個問題很複雜」、「兩者不一樣」、「明白了」這類開場。」
— the old opening plus the named ban — and it re-measures at 5/5 called
on both channels with the preamble examples still in force. 「明白了」
joined the list after a real conversation opened with 「Lulo 明白了，您現
在想知道…」; the first attempt to add it also banned restating the
question in general words — 「不要複述問題」 — and that clause alone took
the spoken channel's tool calls from 5/5 to 0/5 while the written channel
kept calling. The general clause went, the named example stayed, and both
channels re-measure at 5/5. Two lessons, third confirmation each: name
the failure instead of describing its category, and re-measure the whole
preface after every edit, because the blast radius of a clause is not
readable from its sentence.

Dropping the absolutism cost something it had been buying silently:
identity. Asked 你叫什麼名字 at temperature 0.7, the model answered
「我叫 Gemma 4」 two to three times in five. One specific sentence about
that one question — 「被問到名字或身分時，你就是 Lulo。」 — restored 5/5 on
both channels. Specific beats absolutist: the C-variant lesson said an
open-ended clause reaches further than its sentence, and this is its
converse — a narrowly-scoped sentence stays where it is put.

The typed channel this section anticipated now exists: `AnswerChannel` in
`composeAgentPrompt`, written by the view model from how the words
arrived, with a `[文字回答方式]` block measured whole in
`WrittenPrefaceProbeTests` — persona 5/5, tools 5/5, spread 27×. Its
first draft replaced 「可以到七八句」 with the open-ended 「把它說完整」 and
measured the C-variant failure both ways at once, which is why its length
lines are the B lines verbatim.
