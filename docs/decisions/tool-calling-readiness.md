# Tool calling is not ready, and the clock did not need it

`CLAUDE.md` said "next up: tool calling with a permission layer" for a long
time. Before designing the permission layer, the question underneath it was
measured: does gemma-4-E4B, the model this app actually runs, decide to call
a tool when it needs one?

Under this app's own system instruction, no. Not once.

## What was measured

`native/inference_service/Tests/InferenceServiceTests/ToolCallProbeTests.swift`
registers one tool — a clock returning the sentinel `TOOL-RAN-4718` — asks
the model the time, and counts how often the sentinel comes back. The tool
is wired through the vendored `ConversationConfig(tools:)`, so a call that
never happens is the model declining, not the plumbing failing.

Every row below comes from a single run of that file, at the sampler
settings the app really uses (`topK` 40 from `LiteRTLMRuntimeBackend`, and
temperature with nucleus probability from `AnswerStyle`), against the
instruction `composeAgentPrompt` really produces — pasted into the probe
whole, not abbreviated. Five attempts each with a different seed, because
one call and one refusal are the same observation until they are repeated.

| Asked to fetch the time with a tool | Called it |
|---|---|
| Chinese, no system message | **5/5** |
| Chinese, this app's instruction | 0/5 |
| Chinese, this app's instruction, `AnswerStyle.steady` | 0/5 |
| Chinese, plus a paragraph ordering it to use the tool | 0/5 |
| English, no system message | 0/5 |
| English, this app's instruction | 0/5 |
| Chinese, no system message, **constrained decoding** | **5/5** |
| Chinese, this app's instruction, **constrained decoding** | 0/5 |
| English, this app's instruction, **constrained decoding** | 0/5 |

| Told the time in the prompt instead | Answered right |
|---|---|
| Chinese, this app's instruction | **5/5** |
| Chinese, this app's instruction, `AnswerStyle.steady` | **5/5** |
| English, this app's instruction | **5/5** |

**The system instruction is the whole story.** With nothing in front of it
the model called the clock every single time. With this app's instruction in
front of it — three blocks, about 250 characters of who it is and how to
speak — it never called it again, in either language, at either temperature,
and not even when a further paragraph told it in as many words to call the
tool and not to guess. This is not a fragile capability that needs coaxing.
Between an empty prompt and this app's ordinary prompt, it goes from always
to never.

**Constrained decoding does not change it, and that was measured after this
file said it would.** The three rows above them are the same three asks with
`ExperimentalFlags.enableConversationConstrainedDecoding` on. The control
moved nothing and proves the flag reached the model: with no system message
the sentinel comes back all five times, formatted by the model as
「現在的時間是 **TOOL-RAN-4718**。」 Under this app's instruction it is still
0/5, in both languages, and the replies are the same invented clocks as
before — 「現在是下午兩點零八分。」, `It is currently 10:45 AM.`, and once
`It is currently 4:71 PM.`, which is not a time at all.

This file used to argue the opposite, in the list at the bottom: "forcing
the tool-call token shape takes the decision away from the model, which is
the only one of these that addresses what was measured." That is a
misreading of what constrained decoding is. It constrains the **shape of
the tokens once the model has decided to call**; it does not make the model
decide. The decision is upstream of the constraint, and the decision is
what this app's instruction is suppressing.

Two claims in that same bullet were also simply wrong about the code.
`native/vendor/litert_lm/swift/` **does** carry constrained decoding —
`ExperimentalFlags.enableConversationConstrainedDecoding` at
`ExperimentalFlags.swift:85`, passed through `Engine.createConversation` at
`Engine.swift:227` — and the Gemma constraint provider **is** in the shipped
binary, which exports `LiteRtLmGemmaModelConstraintProvider_Create`,
`…_CreateConstraintFromTools`, a whole llguidance engine, and the string
`CONSTRAINT_MODE_FUNCTION_CALL_ONLY`. What was missing was any call to
`optIntoExperimentalAPIs()` in the probe, so every row above the constrained
ones was measured with it off. It reads like the search was for
`enableConstrainedDecoding` and missed the `Conversation` in the middle of
the real name.

All nine original rows re-run unchanged alongside the new three, from one
artifact, so the two halves of the table are comparable.

**The failure is silent, and once it was worse than silent.** It does not
say it cannot read a clock. It returns 「現在是下午兩點零一分」, `1:17 PM`,
`11:17 AM` — different every time, all confident, all wrong, from an app
whose core instruction says 不捏造資訊. One reply at `AnswerStyle.steady` was
「我現在可以幫你查一下時間。請稍等一下喔。」 — it said it would look the time up,
and then did not.

## The larger model was the last lever, and it is spent

`gemma-4-12B-it` was the one option left that did not cost the persona. It
was installed and run against the same probe, and it is worse than the model
it would replace.

| gemma-4-12B-it, GPU backend | Called it |
|---|---|
| Chinese, no system message | **0/5** |
| Chinese, this app's instruction | 0/5 |
| Chinese, no system message, **constrained decoding** | runtime error |

| Control, gemma-4-E4B-it, **GPU** backend | Called it |
|---|---|
| Chinese, no system message | **4/5** |

**The control is the row that makes the rest readable.** Every E4B number in
the tables above was measured on the CPU backend, and 12B is too large to
decode on CPU in a sitting, so the obvious reading — "the bigger model
declines" — was at risk of being a comparison between two backends. E4B was
re-run on the GPU backend the app actually uses on arm64 and still calls the
clock, 4/5. The backend is not the explanation. (4/5 rather than 5/5 is one
sample at n=5; it is not a claim that GPU is worse.)

**What is not established: whether 12B ever saw the tool.** The only
evidence anywhere in this file that a tool declaration reaches the model is
that a model called it, and 12B never did. Its artifact carries the same
function-calling metadata as E4B's — `<|tool>`, `<|tool_call>`,
`use_template_for_fc_format: true`, and the `{%- if tools -%}` block that
renders declarations into the system turn — but a declaration that is
rendered and a declaration that is attended to are not the same claim. The
test that would separate them is constrained decoding, which forces the call
shape: a sentinel coming back would prove the tool is reachable and the
model was choosing not to reach for it. **It cannot be run.** On 12B with
the GPU backend it fails inside the runtime, not in the model:

```
INTERNAL: llm_litert_compiled_model_executor.cc:1266
└ convert_tensor_buffer.h:134
└ litert_tensor_buffer.h:861
```

So the 0/5 above is honest about what it counts — the sentinel did not come
back — and silent about why. Do not quote it as "12B refuses to call tools".

**It is unusable here for reasons that have nothing to do with tools.**
Measured by `FirstReplyLatencyTests` on this M1 Pro, with the weight cache
already built: `engine.initialize()` 59.5s and first token 17.4s, against
E4B's 362ms for a settled Chinese turn. The cache does not help — the cold
run was 53.6s, so the load is compute, not I/O. And roughly one generation
in seven ends in `ABORTED: The timeout was reached while reading back data`,
a GPU readback deadline that ended the shortest condition in the table as
readily as the longest. A model that aborts intermittently cannot be put on
any path, fast or slow.

Which closes the list. Constrained decoding was measured and does not
address the decision; a larger model does not restore the decision and
cannot run here anyway. What is left costs the persona (a much shorter
system instruction) or takes the decision away from the model entirely (a
router). Neither is a measurement — they are designs, and they belong to
whoever picks tool calling up next.

## What was done instead

The clock is told, not fetched. `composeAgentPrompt` takes a `now` and puts
it in the turn instruction ahead of the question. Ten out of ten in Chinese
against zero out of five for the tool, under the same instruction the app
sends, at both temperatures.

It goes in the **turn** half, not the stable half. `voice-turn-latency.md`
measured the system instruction being re-prefilled at 1648 ms against 362 ms
when it is prefilled once; a clock inside it would expire between every
question and pay that cost every turn. The turn half is re-read anyway, and
a timestamp is a dozen tokens of it. Read per turn rather than per provider,
so an app left open overnight does not spend the next day insisting it is
still yesterday.

**English is not weaker. That was the scorer.** This section used to read
3/5 against Chinese 5/5 and treated the gap as a property of the model —
"two in five saying something else is not good enough to call finished, and
the English clock ships knowing that." It shipped knowing something that was
not true. The minute list was `["53", "五十三"]`: Chinese was allowed both
its digits and its numerals, English only its digits, so `It's two
fifty-three in the morning.` scored wrong. With the two languages spelled
out evenly, English told is **5/5**, and every other row in this file
re-runs unchanged.

The five replies say which two were being thrown away, so this is not an
inference from the totals moving:

```
right 1: It is currently 2:53. …
right 2: It is currently two fifty-three in the morning. …
right 3: It is currently 2:53.
right 4: It is two fifty-three in the morning right now. …
right 5: It is 2:53 in the morning right now. …
```

Two of the five spell the minute out. Five minus those two is exactly the
3/5 this file used to report, and both of them read the handed clock back
correctly.

An earlier explanation had already been checked and ruled out, and it stays
ruled out. The English instruction used to carry a Chinese sentence — the
built-in tone was rendered raw into both languages, so every English prompt
this app sent ended `Tone: 親近但不裝熟.` — which in a composer whose own
comment says a small model answers in the language it was instructed in is
exactly the kind of thing that would explain a weak English column. It was
fixed, the prefaces were regenerated from the composer, every condition was
re-run, and all nine numbers came back identical. That was the right check,
aimed at a gap that was never in the model.

## Scoring this is where it keeps going wrong

Three times now, in this one file.

1. Compared against the literal string `02:53`, marking 「凌晨 2 點 53 分」
   wrong.
2. Added a handful of spellings and still marked 「現在是凌晨兩點五十三分」
   wrong — the same answer in Chinese numerals — after this file already
   carried the lesson.
3. Held 「五十三」 and no English word form, so the same clock spelled out
   scored right in one language and wrong in the other.

All three ran the same direction: they understated the option being argued
for. An error that flatters the alternative is the kind that survives
review, because the conclusion does not move — only the margin does.

The third is worse than the first two and worth naming separately. A scorer
whose spellings are uneven between two languages does not merely understate
a column; it **manufactures a difference between the languages**, and that
difference then reads as a finding about the model. Two paragraphs of this
file were written about a weakness that was in the list of strings above.
When a measurement spans languages, check that both sides are allowed the
same forms before believing any gap between them.

The probe now prints **every reply that scored wrong**, not the last reply
of each condition. A column reading 3/5 is a number until those two misses
can be read: a time the model invented and a real one the scorer could not
parse are the same number and completely different problems. The difference
is obvious once printed — 「現在是下午兩點零七分」 five times over is a model
making one up, and it looks nothing like `It is 2:53 in the morning right
now.`

## What this rules in and out

Not everything that looks like a tool should be one. A fact that is cheap,
small, and always available is context; the model does not need to decide to
ask for it, and letting it decide is where the failures come from. Date and
time are the clearest case and are now handled.

Tool calling is still the right shape for what is left — anything with a
side effect, anything expensive, anything whose result is too big or too
variable to send unconditionally. But it needs the model to decide, and
under this app's prompt it does not decide, ever. A permission layer over a
capability that fires zero times in thirty is a permission layer over
nothing. One of these has to change first:

- ~~**Constrained decoding.**~~ **Ruled out, by measurement.** It is present
  in the vendored wrapper and in the shipped binary, it was turned on, and
  the app-instruction rows stayed at 0/5 while the control stayed at 5/5.
  See the table above. It shapes the tokens of a call the model has already
  decided to make, and the decision is what is missing.
- **A much shorter system instruction**, which the 5/5 row shows would help
  — and which costs the persona, the spoken-answer rules, and the length
  budget that `agent_prompt_composer.dart` documents as earned.
- ~~**A larger model.**~~ **Tried, on `gemma-4-12B-it`, and it does not
  help.** 0/5 with no system message where E4B is 4/5 on the same backend,
  59.5s to load and 17.4s to first token on this machine, and about one
  generation in seven aborted by the GPU driver. See the section above,
  including what that 0/5 does and does not establish.
- **A router that decides instead of the model** — cheap to write, and it
  fails on exactly the phrasings nobody anticipated, which is most of them.

Re-run the probe before believing any of this again. It is checked in and
skipped by default; a new model or a re-vendored runtime invalidates the
tables above, not the method. If you change the conditions, re-run all of
them and rewrite both tables — an earlier version of this file quoted rows
from three different probe builds and could no longer reproduce its own
numbers.

```sh
cd native/inference_service
REAL_GEMMA_MODEL_PATH="…/Lulo/models/gemma-4-E4B-it.litertlm" \
  swift test --filter ToolCallProbeTests
```

Two environment variables narrow it, and both change what a row means, so
say which one produced any number quoted anywhere. `TOOL_PROBE_BACKEND=gpu`
selects the backend the app uses on arm64 — the tables above are CPU unless
they say otherwise. `TOOL_PROBE_ONLY` takes comma-separated labels, matched
exactly, for when reloading a model sixty times is an hour of a machine; it
fails the test if it matches nothing, because a misspelled label would
otherwise run zero conditions and pass.

The prefaces in the probe are pasted from the real composer. Regenerate them
with `dart run tool/dump_preface.dart` in `packages/agent_core` if the
profile changes, or the probe will be measuring a prompt the app stopped
sending.

## Loose thread

Answers wandered past the question — 「需要我幫你設定任何提醒嗎？」, "Would you
like me to tell you anything else about the time?", "I can also check the
exact time if you need more detail" — in a profile whose instruction is
三句話以內 and whose whole point is to stop after the core. Offering to check
the time it was just given is its own small problem. Neither is addressed
here.
