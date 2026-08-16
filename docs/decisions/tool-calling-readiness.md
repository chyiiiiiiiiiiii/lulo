# Tool calling works, and the file that said otherwise was measuring quoting

For a year this file was titled "Tool calling is not ready", and `CLAUDE.md`
repeated it: probed against the real model, gemma-4-E4B called a registered
clock 5/5 with no system message and **0/5 under this app's own system
instruction**, in either language, at either temperature, with constrained
decoding on or off, even when a paragraph ordered it to use the tool.

Every part of that was reproducible, and the conclusion drawn from it was
wrong. Measured on runtime v0.16.0 with the scorer fixed, on the GPU
backend the app uses, against the prefaces the composer emits as of
2026-08-16 (the reconciled opening line and the identity anchor — see the
last sections of `answer-length-should-follow-the-question.md` for why
those lines are what they are):

| Asked to fetch the time with a tool (gemma-4-E4B, GPU) | Called | Quoted |
|---|---|---|
| Chinese, no system message | **5/5** | 5/5 |
| Chinese, **this app's instruction** | **5/5** | 5/5 |
| Chinese, this app's instruction, `AnswerStyle.steady` | **5/5** | 5/5 |
| Chinese, plus a paragraph naming the tool | **5/5** | 5/5 |
| English, no system message | **5/5** | 5/5 |
| English, this app's instruction | **5/5** | 5/5 |
| Chinese, no system message, constrained decoding | **5/5** | 5/5 |
| Chinese, this app's instruction, constrained decoding | **5/5** | 5/5 |
| English, this app's instruction, constrained decoding | **5/5** | 5/5 |
| Chinese, instruction as `initialMessages[0]` | **5/5** | 5/5 |

The table is one preface edit away from zero, and that was measured the
hard way: the opening line 「第一句就要是答案本身」 — adopted for preamble
suppression before tools worked, never re-probed — took every app-preface
row to **0/5 called**, on both channels, and the ablation named it as the
single cause. A model told the first sentence must *be* the answer cannot
stop to call a tool first. The line was reworded to keep the measured
active ingredient (the named preamble ban) without the absolutism, and
`WrittenPrefaceProbeTests` now guards persona, spread, and calling on
both channels so the next preface edit is measured before it ships
rather than after.

| The precision half | Called |
|---|---|
| Chinese, this app's instruction, unrelated question (生日祝福) | **0/5** |
| English, this app's instruction, unrelated question | **0/5** |
| Told the clock in the prompt instead (all three told rows) | **0/5** |

| Told the time in the prompt instead | Quoted |
|---|---|
| Chinese, this app's instruction | **5/5** |
| Chinese, this app's instruction, `AnswerStyle.steady` | **5/5** |
| English, this app's instruction | **5/5** |

The model calls the tool every time it needs one, under the full persona, in
both languages. It never calls it for a question a tool does not serve, and
never calls it when the answer is already in the prompt. Recall five out of
five, zero spurious calls out of fifteen chances. This is what "ready" looks
like.

## The instrument failure that manufactured the old table

The old tool answered with the sentinel `TOOL-RAN-4718` — a string no model
produces by accident — and the scorer searched the **final text** for it.
That proves the tool ran when the sentinel is there. It proves nothing when
it is not, and the old conclusion lived entirely in that asymmetry.

What was actually happening, established by counting `run()` executions
directly: under the app's instruction the model **called the tool, was
handed a string that is not a time, and answered like the spoken-Chinese
assistant it was told to be** — 「現在是下午兩點零七分。」, three short
sentences, no markdown, and no unpronounceable sentinel. Without the
instruction it parroted the sentinel back verbatim. The scorer turned that
difference in *quoting* into a table about *calling*: 5/5 bare, 0/5 under
the preface — and the stronger the persona, the more the laundering, so the
instrument punished exactly the condition under investigation.

The replies were sitting in the probe's own output the whole time, saying
so. 「我現在可以幫你查一下時間。請稍等一下喔。」 was quoted in an earlier
version of this file as the model "saying it would look the time up, and
then not doing it." It did it. The evidence was filed under mockery.

Two changes to the probe close this class of error:

1. **Called is counted by execution.** The tool body increments a counter;
   the final text has no vote in that column. A unit test pins the
   asymmetry so it cannot be reintroduced.
2. **The tool answers with a readable clock** (`02:53`), so the *quoted*
   column can be scored on the minute the way the told rows always were —
   fifty-three is one minute out of sixty, which is as much sentinel as a
   quoting check needs, and it is something a persona can actually say.

## What is attributable to what

The fixed table was taken on runtime v0.16.0; the old one on v0.14.0 with
the old scorer. Both variables moved, so whether v0.14.0 was also calling
under the preface — with the sentinel laundering hiding it — cannot be read
off these tables and was not worth an archaeology expedition to establish.
Two things are certain: the pip 0.16.0 dylib reproduces the whole mechanism
(sentinel-shaped tool → invented-looking times; readable clock → 4/5 called
and quoted, one seed announcing it would check and stopping), and on the
vendored v0.16.0 with executions counted, every condition calls.

The upgrade to v0.16.0 stands on its own regardless: it brought
`automaticToolCalling`, `Message.toolCalls`, per-call `maxOutputTokens` in
the official API, and the tool-response message shape — the machinery an
actual integration needs. See `native/vendor/litert_lm/PATCHES.md`.

## The clock stays told

None of this reopens the clock. Telling it in the turn instruction is 5/5
quoted at zero extra generations, zero extra tokens of loop, and zero
latency; fetching it is 5/5 called and 4–5/5 quoted **plus a tool round
trip**. A fact that is cheap, small, and always available is context, not a
tool — the model does not need to decide to ask for it, and the told rows
show it knows not to (0/5 calls with the clock in the prompt). The clock
goes in the **turn** half for the reason `voice-turn-latency.md` measured:
the stable half is prefilled once, and a timestamp inside it would expire
between every question and re-prefill 1648 ms against 362 ms.

Tool calling is for what telling cannot do: side effects, expensive
lookups, results too big or variable to send unconditionally. That is now a
capability this app can build on — with a permission layer over it, which
is no longer a layer over nothing.

## Scoring this is where it keeps going wrong

Four times now, in this one file.

1. Compared against the literal string `02:53`, marking 「凌晨 2 點 53 分」
   wrong.
2. Added a handful of spellings and still marked 「現在是凌晨兩點五十三分」
   wrong — the same answer in Chinese numerals — after this file already
   carried the lesson.
3. Held 「五十三」 and no English word form, so the same clock spelled out
   scored right in one language and wrong in the other, and two paragraphs
   were written about an English weakness that was in a list of strings.
4. Read "did not quote the sentinel" as "did not call the tool", and built
   a year of product doctrine on the difference.

All four ran the same direction: they understated the option being argued
for or about. An error that flatters the alternative survives review,
because the conclusion does not move — only the margin does. The fourth is
the expensive one, and its shape is general: **a check that is proof in one
direction is not evidence in the other.** The sentinel's presence proved the
tool ran; its absence was silently promoted from "not proven" to "did not
happen", and the promotion is invisible in a table because both read `0/5`.

The probe prints every reply with both flags (`called+quoted`,
`called+unquoted`, `silent+unquoted`), not the last one seen, and appends
the report to `TOOL_PROBE_REPORT` when set — a five-minute measurement
whose stdout the test runner ate was run for nothing.

## gemma-4-12B-it

Its calling rows were measured with the old sentinel scorer on the old
runtime and establish nothing about calling; they are struck, not restated.
What stands, because it never depended on the scorer: on this M1 Pro the
12B is unusable for ordinary reasons — `engine.initialize()` 59.5 s warm
(53.6 s cold, so the load is compute, not I/O), first token 17.4 s against
E4B's 362 ms, and roughly one generation in seven killed by
`ABORTED: The timeout was reached while reading back data`, a GPU readback
deadline that struck the shortest prompt as readily as the longest.
Constrained decoding on 12B/GPU fails inside the runtime
(`convert_tensor_buffer.h:134`). A machine that runs it comfortably can
re-ask the calling question with the fixed probe in two rows.

## Re-running it

```sh
cd native/inference_service
REAL_GEMMA_MODEL_PATH="…/Lulo/models/gemma-4-E4B-it.litertlm" \
  TOOL_PROBE_REPORT=/tmp/probe.txt \
  swift test --filter ToolCallProbeTests
```

It is checked in and skipped by default; a new model or a re-vendored
runtime invalidates the tables above, not the method. If you change the
conditions, re-run all of them and rewrite every table — an earlier version
of this file quoted rows from three different probe builds and could no
longer reproduce its own numbers.

Two environment variables narrow it, and both change what a row means, so
say which one produced any number quoted anywhere. `TOOL_PROBE_BACKEND=gpu`
selects the backend the app uses on arm64 — the tables above are CPU unless
they say otherwise (E4B calls on GPU too: 5/5 on the readable-clock probe's
predecessor run). `TOOL_PROBE_ONLY` takes comma-separated labels, matched
exactly, for when reloading a model sixty times is an hour of a machine; it
fails the test if it matches nothing, because a misspelled label would
otherwise run zero conditions and pass.

The prefaces in the probe are pasted from the real composer. Regenerate them
with `dart run tool/dump_preface.dart` in `packages/agent_core` if the
profile changes, or the probe will be measuring a prompt the app stopped
sending.

## Loose thread

Answers wander past the question — 「你需要我幫你做什麼嗎？」, "Would you
like to know the date as well?" — in a profile whose instruction is
三句話以內 and whose whole point is to stop after the core. Offering to
check more after answering is its own small problem and is not addressed
here.
