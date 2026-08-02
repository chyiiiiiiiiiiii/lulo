# Qwen Transcript Shadow Design

## Purpose

Evaluate whether a small local Qwen text model improves finalized Taiwan
Mandarin transcripts without allowing it to affect Lulo's live conversation.
The deterministic refiner remains the production authority. Qwen runs as a
late, disposable shadow candidate whose output is useful only for evaluation.

The existing Qwen3-TTS sidecar is not a text model and cannot perform this
work. The shadow provider therefore has its own optional localhost boundary
and text-model lifecycle. This first implementation establishes the typed,
testable App-side shadow path; installing or downloading a model remains an
explicit developer operation in a separate scope.

## Goals

1. Copy each non-empty finalized voice utterance to a shadow proposal path
   after the live deterministic refinement has been submitted.
2. Send only the utterance, `zh-TW`, and the vocabulary relevant to that
   utterance. Never send conversation history, memories, full profile data,
   or previous transcripts.
3. Validate every proposal through the existing `TranscriptProposalGate`.
4. Record enough typed evidence to export Qwen and deterministic candidates
   through the existing Taiwan Mandarin voice-eval schema.
5. Make shadow work bounded, cancellable, offline, and unable to delay or
   mutate the user-visible turn.

## Non-goals

- Selecting a Qwen proposal for production conversation text.
- Reusing Qwen3-TTS weights as a language model.
- Sharing the live Gemma conversation session or inference slot.
- Automatically downloading, launching, or keeping a Qwen text model alive.
- Automatically writing private transcript artifacts to disk.
- Sending transcript content over a non-loopback interface or the internet.
- Changing endpoint ownership or integrating Pipecat Smart Turn.

## Chosen architecture

### Core shadow types

`agent_core` owns provider-independent immutable values:

- `TranscriptProposalRequest`: raw finalized transcript, locale, protected
  vocabulary, request ID, and deadline.
- `TranscriptProposal`: proposal text, provider identity and version, and
  elapsed time.
- `TranscriptShadowResult`: raw transcript, optional proposal, safety-gate
  verdict, terminal status, provider metadata, and elapsed time.
- `TranscriptProposalProvider`: one async proposal interface.

These values contain no logging behavior and own immutable copies of every
collection.

### App-side coordinator

`TranscriptShadowCoordinator` accepts a proposal provider and a result sink.
The voice controller gives it a finalized utterance only after starting the
normal deterministic refinement. Shadow submission is fire-and-forget and is
never awaited by the live turn.

The coordinator permits one in-flight request. If another final arrives while
the provider is busy, the newer request is reported as skipped rather than
queued. This prevents conversational bursts from growing a private transcript
backlog. A generation epoch fences late results after voice disable, session
replacement, or disposal.

Provider success is not acceptance. The coordinator sends the returned string
through `TranscriptProposalGate` with the exact raw transcript and scoped
vocabulary. Accepted and rejected proposals both become evaluation evidence;
neither becomes conversation state.

### Optional localhost provider

`LoopbackTranscriptProposalProvider` communicates with an explicitly running
developer sidecar on `127.0.0.1`. Its endpoint is configured through a
developer-only composition value and defaults to disabled.

The request JSON contains:

```json
{
  "schemaVersion": 1,
  "requestId": "opaque-id",
  "locale": "zh-TW",
  "rawTranscript": "current finalized utterance only",
  "protectedVocabulary": ["only", "matching", "terms"]
}
```

The response must contain the same schema version and request ID plus a single
non-empty `refinedTranscript`, provider name, and provider version. Unknown
fields are ignored; malformed, mismatched, non-2xx, oversized, timed-out, or
non-loopback responses become typed failures without transcript logging.

The provider accepts only `http://127.0.0.1` or `http://[::1]`. It has strict
request and response byte ceilings and no redirects. It never starts a
process, downloads weights, or retries.

## Data flow

1. Native ASR emits a non-empty final transcript.
2. `VoiceConversationController` starts the current deterministic refiner.
3. In parallel, when shadow mode is explicitly enabled, the controller hands
   an immutable request to `TranscriptShadowCoordinator` without awaiting it.
4. Deterministic refinement completes or falls back within 250 ms and the
   selected live turn is submitted exactly as today.
5. The proposal provider may return later. The coordinator validates its
   protocol identity and runs `TranscriptProposalGate`.
6. A bounded in-memory sink retains evaluation results by explicit corpus case
   ID when one was supplied by development tooling. Normal production voice
   turns have no corpus case ID and are reduced to transcript-free counters.
7. Explicit development code may pass retained case results to
   `buildTranscriptCandidateExport`; no component writes files automatically.

## Privacy and observability

Logs may include request ID, status, elapsed milliseconds, provider identity,
response byte count, safety rejection categories, and edit count. Logs must
never include raw text, proposal text, vocabulary values, URLs, emails, or
replacement fragments.

The default composition uses a disabled coordinator. Enabling shadow mode is
an explicit developer configuration, visible in startup diagnostics. The
loopback provider rejects hostnames such as `localhost` to avoid resolver
ambiguity and rejects redirects that could leave the machine.

Only evaluation runs with explicit case IDs retain transcript-bearing results
in memory. Ordinary use records aggregate statuses only. Disposal clears all
in-memory evidence.

## Failure behavior

- Disabled: no request is created.
- Busy: the new request is skipped and never queued.
- Timeout, connection error, malformed JSON, oversized response, mismatched
  request ID, or disposal: record a redacted failure status.
- Empty or unsafe proposal: retain a rejected evaluation result when a case ID
  exists, but never select it.
- Late response after an epoch change: discard it completely.
- Sink exception: swallow it after a redacted diagnostic; live voice remains
  unaffected.

No shadow failure may change the deterministic refiner result, pending turn,
answer generation, barge-in state, or TTS behavior.

## Evaluation and promotion gates

The existing `voice_eval` candidate contract remains authoritative. Explicit
golden runs compare raw, deterministic, and Qwen outputs using identical case
IDs. Qwen remains shadow-only until a separate reviewed decision confirms:

- zero protected-token violations;
- no case with worse spoken CER than raw;
- aggregate literal CER no worse than deterministic;
- p95 proposal completion at or below 250 ms on the target Mac;
- no meaning-changing edit in manual review.

Failure to meet latency does not invalidate quality evidence, but it prevents
promotion to the live path.

## Testing

Red/Green tests cover:

1. immutable proposal requests and results;
2. coordinator success, safety rejection, busy skip, exception, disposal, and
   stale-result fencing;
3. proof that live submission completes without awaiting shadow work;
4. loopback-only endpoint validation and redirect rejection;
5. request/response schema, request-ID matching, byte ceilings, malformed JSON,
   timeout, and redacted diagnostics;
6. explicit-case evidence export and absence of automatic filesystem writes;
7. complete repository verification with no live sidecar or model required.

Real Qwen quality and latency runs are manual development evidence because
they require an explicitly installed local model and the private audio corpus.

## Delivery slices

1. Provider-independent core values and coordinator with an in-memory test
   provider.
2. Voice-controller shadow dispatch and disabled-by-default composition.
3. Hardened loopback HTTP provider behind explicit developer configuration.
4. Bounded evaluation sink and candidate export bridge.
5. Separate model-sidecar installation and Qwen golden-corpus experiment.

The first four slices belong to this repository. Slice five is deliberately a
separate change because it introduces model weights, Python dependencies, and
a new long-lived process.
