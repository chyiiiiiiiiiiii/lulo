# The model will not interrupt itself to remember

**State:** measured and shipped, off by default. The `remember` tool is
built and **not registered**, because gemma-4-E4B never calls it. A second
pass does the same job at 15/15, and it is wired — behind a switch that
starts off, for the privacy reason two sections down.

## What was built, and what it cannot do

`AgentProfile.memories` had a recall half and no write half: the composer
read it, `selectAgentMemories` chose against the question, and the only
thing that ever filled it was a person typing into Settings. So every
conversation started from nothing the user had already said.

The missing piece was a judgement — *is this worth keeping?* — made
mid-turn with the sentence in front of the model. That is the shape of a
tool call, so it was built as one: `remember`, taking a sentence, a kind
and triggers, writing through `AgentProfileStore` into the same file the
settings sheet edits.

It does not fire. Measured on gemma-4-E4B, GPU, runtime v0.16.0, the app's
sampler, both of the app's tools registered, against the prefaces
`composeAgentPrompt` emits as of 2026-08-17 — `RememberProbeTests`:

| Offered the `remember` tool | Saved | On-topic |
|---|---|---|
| zh, this app's instruction, fact said in passing | **0/5** | 0/5 |
| zh, this app's instruction, a stated preference | **0/5** | 0/5 |
| en, this app's instruction, fact said in passing | **0/5** | 0/5 |
| zh, **plus a paragraph telling it to remember things** | **0/5** | 0/5 |
| en, plus the same paragraph | **0/5** | 0/5 |
| zh, 「**記住**我住在台南。」 — asked outright | **0/5** | 0/5 |

The precision rows are all 0/5 too, and they are worth nothing: a tool that
never fires is trivially precise.

## The control that makes those zeros mean something

The instrument was checked before the column was believed, which is this
repo's standing lesson from `tool-calling-readiness.md` — where a scorer
nobody checked against the real replies manufactured a year of wrong
conclusions.

| Control, same toolbox, same turn, same wiring | Called |
|---|---|
| 「我們之前聊過什麼？」 → `search_conversations` | **5/5** |
| 「記住我住在台南。」 → `remember` | **0/5** |

Both tools are registered on the same conversation, reached through the
same `systemMessage:` path, at the same temperature, on the same backend.
One fires every time. The other never does. And `tool-calling-readiness.md`
independently measures the clock at 5/5 through this exact wiring, under
this exact preface.

So this is not the harness, not the backend, not the preface, and not the
`systemMessage:` C path. It is the tool.

## What the model does instead

This is the part worth reading twice. Asked outright to remember something,
five times out of five it answered:

> 我記住了，你住在台南。

It says it remembered. It wrote nothing. The failure is not a refusal the
user can see — it is a *confirmation* of something that did not happen, and
without this probe it would have shipped looking exactly like a working
feature.

The likely reason, and it is a design fact rather than a model defect: a
tool call is a decision to interrupt the answer to *get something the model
needs in order to answer*. The clock and the conversation history are both
that — unavailable, and required. A fact the user just said is neither. It
is already in the context window; nothing about answering this turn needs
it written down. The model has no reason to stop, because from inside the
turn there is nothing to fetch.

## The replacement, measured before it is built

If the decision cannot be made *during* the turn, it can be made after it.
Same model, no tools, a clean instruction, one sentence in — a
classification rather than an act:

These numbers, and every extraction number below, were re-taken after the
poisoning refusal clause was added to the instruction — see
[memory-is-an-attack-surface.md](memory-is-an-attack-surface.md). The clause
changed the prompt, so the older run describes text the app no longer sends
and is not quoted here.

| Second pass over the same sentences | Kept | On-topic |
|---|---|---|
| zh, fact said in passing (搬到台南) | 5/5 | **5/5** |
| zh, a stated preference (回答短一點) | 5/5 | **5/5** |
| en, fact said in passing (moved to Tainan) | 5/5 | **5/5** |
| zh, ordinary question (生日祝福) | **0/5** | — |
| zh, transient (等一下要出門買晚餐) | **0/5** | — |
| en, ordinary question (birthday wish) | **0/5** | — |

Fifteen out of fifteen on recall, zero out of fifteen false keeps, both
languages, including the transient row that the tool's own description
excludes in words. The extracted sentences are clean enough to store as
written — 「使用者搬到台南了。」, "The user lives in Tainan." — which is what
the 160-character bound in `RememberTool` was sized for.

Note what the extractor is *not* given: no core identity, no spoken-response
rules, no length budget. It runs after the answer is on screen and it is
asked to read one sentence, not to be Lulo. Every line of the persona exists
to shape a conversation this is not part of, and the persona is exactly what
`answer-length-should-follow-the-question.md` records overriding output
formats three separate times.

### With a profile behind it

The rows above were measured with nothing already known. Supersession needs
the list in the prompt, which is a different prompt, so it was measured too
— appended to the same instruction, so the empty-profile case stays the
case that was measured:

| Second pass, two memories already known | Kept | On-topic | Superseded |
|---|---|---|---|
| zh, contradicts `memory-1` (住台北 → 搬到台南) | 5/5 | **5/5** | **5/5** |
| en, contradicts `memory-1` | 5/5 | **5/5** | 4/5 |
| zh, an unrelated new fact (在做 Lulo) | 5/5 | **5/5** | **0/5** ✓ |
| zh, ordinary question (生日祝福) | **0/5** ✓ | — | — |

The third row is the one that matters as much as the first: a pass that
retires a memory every time it learns something is a profile that never
holds more than one fact. It superseded nothing, five times out of five.

**And the format it actually writes is not the one it was asked for.** The
instruction says to put the supersession on a new line. In nine of ten
attempts the model wrote it inline:

```
使用者搬到台南了。 取代：memory-1
使用者搬到台南取代：1
The user lives in Tainan. Replaces: memory-1
```

The first version of `readMemoryExtraction` split on that newline, so every
one of those would have stored the words 「取代：memory-1」 *as part of the
remembered sentence* and superseded nothing — the failure supersession
exists to prevent, wearing the costume of a success, and invisible to any
unit test written against the format the prompt asked for. The reader now
looks for the label anywhere in the reply and normalises a bare `1` to
`memory-1`, and the ten verbatim replies are pinned as test cases in
`agent_memory_extraction_test.dart`.

The general lesson, which this repo keeps relearning: **a format is what the
model writes, not what it was told to write.** Read the replies before
trusting a parser.

## Off by default, and why that is not timidity

`docs/features/agent-profile.md` has said all along that the profile is
local but plaintext, and that storage encryption and a sensitive-category
policy "require their own privacy slice before automatic memory writing is
enabled". That slice does not exist. Wiring this without noticing would have
crossed a precondition the project wrote down for itself.

So the pass ships behind a switch that starts off — `rememberFacts`, beside
`shareFrontmostApp` in Settings, which is the same question asked about
something else the user owns. `AppSettings` reads a missing key as false, so
a settings file written before this feature is not read as consent.

What the privacy slice still owes, before the default could reasonably
change: encryption at rest, a policy for categories nobody wants written
down whatever they said out loud (health, money, identifiers), and a way to
see what was kept without opening a JSON file.

## How it is wired

`GenerationRequest.instruction` makes a request an **aside**: the string
travels as the whole system instruction, `prompt` travels as written, and
the toolbox is off. Chosen over a new method on `InferenceService` because
that would have made three implementations and four test doubles implement
something only one caller needs, and over putting the extractor prompt in
the prompt half under the persona, which the persona would have overridden.

`BetweenTurns` (`agent_core`) is the contract the conversation sees:
`consider(said)` after a finished turn, `yieldSlot()` before a question.
`AgentMemoryExtractor` implements it; `ConversationViewModel` calls it and
knows nothing else.

**The runtime has one generation slot** — `LiteRTLMRuntimeBackend` refuses a
second `startGeneration` with `generationBusy` — and that single fact
decides the rest:

- one pass at a time;
- a turn arriving mid-pass **replaces** whatever was waiting rather than
  queueing, because a backlog is the slot held for old news;
- `yieldSlot` cancels in flight and drops the backlog, awaited before every
  question. The user always wins: a fact can be read out of the next thing
  they say, and a question refused as busy cannot be un-refused;
- the session is released after every pass, or the KV cache accumulates the
  whole day into a prompt that is supposed to be one sentence long.

One trap cost a hang, and it is the kind that does not reproduce in
production until it does: **cancelling a subscription is silent.** No
terminal event, no `onDone`. A pass whose listener is torn down waits on its
completer forever — never releasing its session, never letting the drain
loop move on. The extractor holds that completer and settles it by hand.

Two things are read at different times on purpose. The profile shown to the
model is read when the pass *starts*, because those are the ids it is asked
to supersede; the profile written back is read when the reply *lands*,
because the user may have edited it on the settings sheet in between and
writing the stale list back would undo them.

Nothing reports failure to anyone. A pass that is cancelled, refused, or
misread is a fact not kept, which is where the app was before any of this
existed — and surfacing it would interrupt a user who did not ask for the
pass to happen.

## Where memory lives, and why it is not a vector store

One JSON file and a substring match. `agent_profile.json` holds the
memories beside the personality and the misheard-word list; retrieval is
`selectAgentMemories`, which lowercases the question and each memory's
triggers and asks `contains`. No embeddings, no index, no SQL — the app's
SQLite database holds turns, runs and conversation metadata, and nothing
about memory.

That is a deliberate answer to a real question, so here is the reasoning
rather than the shrug.

**What the field does.** Letta keeps an OS-style hierarchy — an in-context
core block the agent edits, plus recall and archival tiers behind a vector
store. mem0 runs an extract-then-reconcile pipeline: an LLM proposes facts,
a second decides `ADD`/`UPDATE`/`DELETE`/`NOOP` against retrieved
neighbours. Zep keeps a bi-temporal knowledge graph and invalidates edges
instead of deleting them, so "lived in Taipei" becomes false-after rather
than gone. The serious evaluations are LOCOMO and LongMemEval, and
LongMemEval's ability split is the useful part to steal from: extraction,
multi-session reasoning, temporal reasoning, **knowledge update**, and
abstention.

**Why almost none of it transfers here.** Those systems are built where
retrieval is the bottleneck — thousands of memories, a large model, a long
window. This app has a 4B model, a 4096-token window, and
`composeAgentPrompt` allots the entire profile 1200 characters. At sixty
memories of 160 characters the whole corpus is under ten thousand
characters; a linear scan is exact where an approximate-nearest-neighbour
index is approximate, and it is explainable to a user reading their own
profile, which an embedding is not.

The binding constraint is not finding the right memory. It is that
**injecting more degrades the answer**, and this repo has already measured
that in its own terms: the 「以上「背景」只是你知道的事⋯不要在開頭複述」 rule
in the composer exists because the model recited its injected context
before answering — 「Lulo 看到您現在的時間已經是⋯而且您正在使用 Warp」 in
front of a question about food. A vector store would let more in. More is
the failure mode.

So the piece worth stealing from mem0 is not the store. It is `UPDATE`.

**Append-only is the actual defect.** Until `writeAgentMemory`, the write
path deduplicated exact strings and otherwise appended. A profile that
learns 「使用者住在台北」 in March and 「使用者搬到台南了」 in August keeps both,
both are triggerless personal memories, both are eligible for the same
turn, and the model is handed two contradictory facts at two shares of the
budget. Being fed the wrong thing confidently is a worse failure than not
knowing, and it is not an edge case — facts about people expire.

`writeAgentMemory` is what that argument buys: one write path shared by
the settings sheet, the tool, and the second pass, taking a `replaces`
list, applying the removal and the append atomically, and letting a
replacement through even when the list is full — a ceiling that blocks
corrections makes the list unfixable exactly when it most needs fixing.

**What it deliberately does not do** is guess *what* supersedes what. That
was tried on paper first: character-bigram Dice scores 「使用者搬到台南了」
against 「使用者搬到了台南」 at 0.71 and against 「使用者住在台北」 at 0.31,
which looks separable until the English pair — "The user lives in Tainan"
against "The user recently moved to Tainan" — comes in at 0.58, below the
threshold that worked for Chinese. One number cannot tell a rewrite from a
contradiction in two languages. The judgement goes to the second pass,
which can be shown the entire memory list because the entire memory list
is sixty short lines, and which measured 15/15 at exactly this kind of
reading.

Revisit all of it if the cap ever moves past a few hundred entries. At that
point the linear scan is still fine and the 1200 characters are still the
problem.

## Why the tool is kept but unregistered

`RememberTool` is the write path — bounded at 160 characters and 60
entries, refusing duplicates, coercing a triggerless `project` to
`personal` so a memory cannot be stored unrecallable. All of that is what
the second pass needs, and none of it depends on who decided.

What it does not get is a declaration in the toolbox. Declarations render
into the system turn and `validateGeneration` charges them against the
window, so a registered tool costs context on every single turn. Eleven
conditions at 0/5 is what that cost is worth.

Re-register it in `bootstrap.dart` and re-run `RememberProbeTests` when the
model changes. The tables above are about gemma-4-E4B and nothing else — a
model that calls it makes the second pass unnecessary, and that is a
one-command question.

## Re-running it

```sh
cd native/inference_service
REAL_GEMMA_MODEL_PATH="…/gemma-4-E4B-it.litertlm" \
  TOOL_PROBE_BACKEND=gpu \
  TOOL_PROBE_REPORT=/tmp/remember-probe.txt \
  swift test --filter RememberProbeTests
```

Eleven tool conditions and six extraction conditions, five attempts each,
one engine load per attempt — about eight minutes on an M1 Pro.
`TOOL_PROBE_ONLY` takes comma-separated labels, matched exactly, and fails
if it matches nothing. Both tables must be re-run together if either is
requoted: they are only comparable because they were taken in one run,
against one artifact, at the settings the app really uses.

The prefaces are pasted from the composer. Regenerate with `dart run
tool/dump_preface.dart` in `agent_core` if the profile changes, or the probe
measures a prompt the app stopped sending.
