# The window guard only ran once

`historyFitting` bounds the context window where a conversation is **built**.
Every turn after the first goes to a conversation the runtime already holds,
and that path never re-seeds — so nothing measured what the live KV cache was
carrying. The guard sat on the path that runs once and was absent from the
path that runs every turn.

This began as a narrower question: the clock now goes into the turn half of
every prompt, so a twenty-turn conversation leaves twenty contradictory
timestamps in the cache. Measuring that turned up the clock as the small term
in a bigger sum nobody was adding.

## What one turn actually leaves behind

The prompt sent to the runtime is not the user's question. It is
`AgentPromptContext.turnInstruction` — the memories this question selected,
the clock, up to `maxDocumentCharacters` of the open document, and then the
question. The answer joins it in the same cache.

Measured with the app's default profile against `localModelContextSize`
(4096) and `localAnswerTokenBudget` (2048), charged the way the runtime's own
`estimatedTokenCount` charges — one token per three UTF-8 bytes:

| | system | turn instruction | per turn held | turns before the cache overflows |
|---|---|---|---|---|
| zh, nothing open | 164 | 31 | 103 | 38 |
| zh, document open | 164 | 152 | 224 | 17 |
| en, nothing open | 188 | 25 | 97 | 40 |

The document row used a four-paragraph note of which the question matched one
paragraph — 113 characters. `maxDocumentCharacters` allows 1400, so a question
that matches more of a longer file costs about 467 tokens a turn on its own,
and the row above is the mild case rather than the bad one.

The clock is 22 tokens a turn in Chinese and 14 in English. Over twenty turns
that is 440 tokens of contradictory timestamps — about a ninth of the window,
and not the reason the window runs out.

## Why it mattered

Overflow does not degrade. It is already measured on the seeding path: 33
turns and 10,093 characters against a 4096-token window produced a stored turn
with status `failed` and no text at all, where the same prompt without history
answered normally. The failure reaches the user as an empty answer, because
the turn that carries the reason is not shown.

So the shape of the bug was: a conversation gets shorter answers from nothing
the user did, and then stops answering, somewhere past the fifteenth turn with
a file open. Nothing in the app would have said why.

## What was done

`liveConversationHasRoomForTurn` charges a turn exactly the way
`historyFitting` charges it — prompt, turn markers, and the reserved answer —
against what the conversation reports it is holding. That figure comes from
`Conversation.getTokenCount()`, which reads the KV cache itself: exact, where
the seeding path is forced to estimate because LiteRT-LM cannot tokenize a
string it has not already prefilled.

A conversation with no room left is **rebuilt**, not trimmed. A KV cache
cannot be trimmed — the runtime exposes no way to drop a prefix of one — so
the rebuild goes through the path that already exists for an edited profile
or a changed sampler, seeded from the history `historyFitting` has already cut
to fit. That history is the raw turns, so the rebuild sheds every accumulated
clock and document passage and keeps what the conversation was actually about.
It costs one prefill and never a model load.

A runtime that will not answer `getTokenCount` leaves the conversation alone.
Reading a failure as "no room" would throw away a live cache on every turn,
which is worse than the thing being guarded against; the seeding budget still
bounds whatever gets rebuilt later.

## What is still not known

Whether the accumulated clocks confuse the model, as opposed to costing
tokens. The most recent one is the last thing it read and a real conversation
genuinely does span time, so there is reason to think not — but that is an
argument, not a measurement, and it needs the real model to settle. The
rebuild makes it moot past the point where it would compound: after a rebuild
only the current turn carries a time.

The rebuild has not been observed against a real model either. It is pinned by
unit tests on the arithmetic and by the driver carrying the window size; the
rebuild itself lives in `SystemLiteRTLMRuntimeDriver`, which has no test seam
and never had one — the same is true of the profile-edit rebuild it reuses.
