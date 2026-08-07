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

| Told the time in the prompt instead | Answered right |
|---|---|
| Chinese, this app's instruction | **5/5** |
| Chinese, this app's instruction, `AnswerStyle.steady` | **5/5** |
| English, this app's instruction | 3/5 |

**The system instruction is the whole story.** With nothing in front of it
the model called the clock every single time. With this app's instruction in
front of it — three blocks, about 250 characters of who it is and how to
speak — it never called it again, in either language, at either temperature,
and not even when a further paragraph told it in as many words to call the
tool and not to guess. This is not a fragile capability that needs coaxing.
Between an empty prompt and this app's ordinary prompt, it goes from always
to never.

**The failure is silent, and once it was worse than silent.** It does not
say it cannot read a clock. It returns 「現在是下午兩點零一分」, `1:17 PM`,
`11:17 AM` — different every time, all confident, all wrong, from an app
whose core instruction says 不捏造資訊. One reply at `AnswerStyle.steady` was
「我現在可以幫你查一下時間。請稍等一下喔。」 — it said it would look the time up,
and then did not.

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

**English is weaker and the number is here rather than hidden**: 3/5, where
Chinese is 5/5. Both failures still put a time in the answer, so what is
being measured is whether it reads back the one it was handed. Two in five
saying something else is not good enough to call finished, and the English
clock ships knowing that.

One obvious explanation was checked and ruled out. The English instruction
used to carry a Chinese sentence — the built-in tone was rendered raw into
both languages, so every English prompt this app sent ended `Tone:
親近但不裝熟.` — which in a composer whose own comment says a small model
answers in the language it was instructed in is exactly the kind of thing
that would explain a weak English column. It was fixed, the prefaces were
regenerated from the composer, and every condition was re-run: **all nine
numbers came back identical, English told included**. Whatever makes English
weaker here, it is not that.

## Scoring this is where it keeps going wrong

Twice. The first pass compared against the literal string `02:53` and marked
「凌晨 2 點 53 分」 wrong. The second added a handful of spellings and still
marked 「現在是凌晨兩點五十三分」 wrong, which is the same answer written in
Chinese numerals — and that was after this file already carried the lesson.
Scoring now looks for the minute in either script and nothing else.

Both mistakes ran the same direction: they understated the option being
argued for. An error that flatters the alternative is the kind that survives
review, so check the scorer against the actual replies before believing a
column.

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

- **Constrained decoding.** The upstream LiteRT-LM has it; the copy in
  `native/vendor/litert_lm/swift/` does not — no `enableConstrainedDecoding`,
  no `ResponseFormat`, and the Gemma constraint provider dylib is not in the
  repo. Forcing the tool-call token shape takes the decision away from the
  model, which is the only one of these that addresses what was measured.
- **A much shorter system instruction**, which the 5/5 row shows would help
  — and which costs the persona, the spoken-answer rules, and the length
  budget that `agent_prompt_composer.dart` documents as earned.
- **A larger model**, at a cost in first-token latency this app has already
  spent a decision doc protecting.
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
