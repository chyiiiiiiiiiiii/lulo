# Tools are declared in Dart, run in Dart, and the loop is the service's

The first working tool call in this app runs like this: the toolbox's
declarations travel as opaque JSON through the Pigeon boundary into
`ConversationConfig`, the native runtime renders them into the chat
template's system turn, and when the model stops to call one, the
generation **ends** with a `toolCall` event instead of `completed`. The
Dart side runs the tool, then starts a fresh host generation on the same
session carrying `toolResponsesJson`; the runtime feeds that to the live
conversation as a tool-response message and streams the actual answer.
`PigeonInferenceService` owns that loop and hides it: the repository sees
one turn — started once, deltas, completed once — however many host
generations the loop spent underneath.

Measured end to end against the real model
(`ToolLoopIntegrationTests`, E4B, the app's own Chinese instruction): the
model asks for `get_current_time`, is handed `{"time":"02:53"}`, and
answers 「現在是凌晨兩點五三分。」 in 3.1 s warm. The decision that this is
worth building at all is `tool-calling-readiness.md`.

## Where each piece lives, and why

| Piece | Lives | Because |
|---|---|---|
| Tool contract, toolbox, wire codecs | `agent_core` (pure Dart) | The next platform reuses them unchanged; `AgentToolbox` is testable without a runtime |
| Tool implementations | App layer (`ConversationSearchTool`) | They touch app-owned capabilities — storage today, panels or notifications later |
| The loop (rounds, errors, cancellation) | `PigeonInferenceService` (Dart) | Everything about it is policy: how many rounds, what an error looks like to the model, and one day, permission |
| Rendering declarations, detecting calls, feeding responses | Native runtime | It owns the template and the KV cache; nothing else can |

This is the repo's standing split — policy shared, mechanism native — the
same shape `turn-taking` reached for its lexicon and matchers.

## What the rest of the world does, and what was taken from whom

- **OpenAI's chat-completions loop** is the wire shape everyone converged
  on: declarations in, a `tool_calls` message out, `role: tool` results
  in, repeat. The runtime's own template and the official `litert-lm
  serve` both speak it, and this app's `toolsJson` / `toolCallsJson` /
  `toolResponsesJson` are that shape with the envelope stripped. Taken
  wholesale — inventing a private schema here would buy nothing.
- **The official Python binding** (`litert_lm`, 0.16.0) runs its automatic
  loop *in Python* over the same C API, with `automatic_tool_calling` as
  the off switch — the caller-owns-the-loop pattern this app follows. Its
  serve handler runs with the loop off and hands calls to the client,
  which is the two-process version of the same decision.
- **MCP** solves tool *distribution* — third-party tools in other
  processes. Nothing here needs a process boundary yet: both shipped
  concerns are in-process and app-owned. The `AgentTool` interface is the
  seam an MCP client would slot behind if that day comes; adopting the
  protocol now would be carrying its weight without its problem.
- **flutter_gemma's agent layer** keeps the loop in Dart too, which was
  confirming but not load-bearing: the reason to keep it in Dart is that
  the permission layer, when a side-effecting tool forces the question,
  must be able to hold the loop open on a user's answer — and that is
  application UI, which Swift-side loop code would have to call back out
  for anyway.

## Roads not taken

**The wrapper's automatic loop** (tools as Swift types, `run()` executing
inside the stream) was the shortest path and was rejected twice over. The
`Tool` protocol keys on `static let name`, so a tool defined in Dart —
where the profile lives and the next platform looks — cannot exist as one;
and execution inside the native stream is exactly where a permission
prompt cannot go. The vendored wrapper needed two narrow patches to make
the caller-owned loop possible at all: the streaming path upstream ignores
`automaticToolCalling` (patch 3), and declarations could only come from
Swift types (patch 4, `toolDeclarationsJson`). See
`native/vendor/litert_lm/PATCHES.md`.

**A dispatcher/two-pass design** — a bare second conversation deciding
tool use, its result told into the persona conversation — was fully
designed while the measured story was still "the persona suppresses the
decision". The corrected measurement dissolved its reason to exist: the
model calls fine under the persona, so paying an extra prefill+decode per
turn to route around a problem that is not there buys latency and a second
KV cache for nothing.

That rejection still stands **for tool use**, and a two-pass design has
since been built for something else, so the two need keeping apart. The
memory pass in `AgentMemoryExtractor` is not a dispatcher deciding whether
to call a tool; it does work the model provably will not do mid-turn at all
— 0/5 at calling a `remember` tool under any condition. It also runs
*after* the answer rather than in front of it, so it costs the user nothing
in latency, where the dispatcher would have paid a prefill before every
reply. If a future change makes it decide tool use, or moves it ahead of
the answer, this paragraph is the one it has to argue with. See
`the-model-will-not-interrupt-itself-to-remember.md`.

**Tool calls as a repository-level event** (surfacing
`GenerationToolCallsRequested` to the caller and letting the repository
drive) would put the loop where durable runs, retry, and the voice path
would all have to learn about it. Hiding it in the service keeps every
existing caller — including `recoverInterruptedRuns` and the retry path —
correct without edits. The seam is not lost: when a tool needs the user's
permission mid-turn, the service takes a callback then, with its first
real caller.

## The details that will bite

- **The tool-call event is terminal on the host side.** The runtime clears
  its single generation slot when it emits `toolCall`, which is what lets
  the continuation start at all. The Dart operation re-aims its event
  filter at the continuation's id (`<id>-tools-<n>`) — the host refuses a
  generation id it has already seen.
- **Continuations repeat the instruction and the declarations verbatim.**
  The native side rebuilds a conversation whose system message or toolbox
  changed (`staleTools`, same rule as `staleInstruction`), and a rebuilt
  conversation has forgotten the calls it was answering. The test pins it.
- **Cancellation between generations.** A turn cancelled while a tool runs
  has no live host generation to cancel; the fence check after the tool
  completes is the whole mechanism, and the test holds a tool open on a
  gate to prove no continuation starts behind a cancel.
- **Three rounds, then the turn fails.** A model looping on tools holds
  the machine's only generation slot; the wrapper's own automatic loop
  caps at 25, which on this machine is minutes. Three is more than any
  turn this app composes has a use for.
- **Declarations spend the window.** They render into the system turn, so
  `validateGeneration` charges `toolsJson` alongside the instruction when
  trimming history — the JSON is longer than what the template renders,
  which errs the direction `estimatedTokenCount` already promises to.
- **An empty toolbox costs what no toolbox ever cost.** `toolsJson` stays
  nil, the conversation is configured exactly as before this feature, and
  the fake runtime never sees any of it.

## The first tool, and what is deliberately not one

`search_conversations` ships first: entirely local, read-only, over data
the app already owns — a permission layer over it would be a layer over
nothing, so shipping it does not require building one. It returns titles
and dates, not transcripts; the result lands inside the same 4096-token
window as everything else.

The clock is deliberately still not a tool. Telling it in the turn
instruction measured 5/5 at zero extra latency, and the model does not
double-fetch what it was told. The dividing line, written down in
`tool-calling-readiness.md`: cheap, small, always-available facts are
context; tools are for side effects and for lookups that are expensive or
variable. The next candidates over that line — reminders, opening a file
the user names — each arrive with the permission question, and the answer
belongs in the Dart loop, which is why the loop lives where it does.

A second tool was built and is **not registered**. `remember` is complete,
bounded and tested, and gemma-4-E4B never calls it — 0/5 across eleven
conditions, against `search_conversations` at 5/5 in the same toolbox on
the same turn. A declaration costs context on every turn, so an
unregistered tool is what a measured zero is worth; the write path it owns
is driven by the extraction pass instead. Re-register it and re-run
`RememberProbeTests` when the model changes. See
`the-model-will-not-interrupt-itself-to-remember.md`.

One thing that is now a tool-adjacent path and is not a tool: an **aside**,
a `GenerationRequest` carrying `instruction`, which sends its own system
text with no persona and no toolbox. It is how the app does work with the
model that is not a conversation turn. It shares the runtime's single
generation slot with real turns, which is why `BetweenTurns.yieldSlot()`
exists — see `features/conversation.md`.
