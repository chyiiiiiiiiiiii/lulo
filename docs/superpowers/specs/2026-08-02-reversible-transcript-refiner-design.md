# Reversible Transcript Refiner Design

## Summary

Lulo will refine finalized Taiwan Mandarin speech without treating a polished
rewrite as ground truth. Every refinement keeps the raw recognizer output,
records the exact edits and policy outcome, and can fall back to raw text at
any point. Partial transcripts remain untouched so barge-in and endpointing
latency do not depend on refinement.

The first production refiner is deterministic and local. A local-LLM proposal
stage uses the same contract in shadow mode until golden-corpus evidence proves
it preserves meaning and meets the latency budget.

## Goals

1. Correct safe presentation issues such as whitespace, known vocabulary
   casing, and conservative punctuation around a final transcript.
2. Preserve raw speech evidence and a machine-readable edit trail.
3. Reject any proposal that changes protected numbers, negation, URLs, email
   addresses, or configured vocabulary tokens.
4. Keep voice submission responsive when refinement fails or exceeds its
   deadline.
5. Produce transcript candidate artifacts consumable by the existing
   `benchmarks/voice_eval` harness.

## Non-goals

- Rewriting partial transcripts.
- Summarizing, translating, completing, or making the user sound more formal.
- Removing fillers or self-corrections in the first production stage.
- Using cloud APIs.
- Enabling an LLM proposal in production before shadow acceptance gates pass.
- Automatically learning correction rules from private transcripts.

## Placement and boundaries

The pure policy lives in `packages/agent_core/lib/src/transcript_refiner/`.
It has no Flutter, platform, storage, or model dependency.

The macOS app owns orchestration in
`apps/local_agent_macos/lib/features/transcript_refiner/`. The
`VoiceConversationController` receives a `TranscriptRefiner`, calls it only
for non-empty final or held utterances, and submits the selected text through
the existing conversation pipeline.

The native Swift speech adapter remains responsible only for audio capture,
ASR, VAD, and finalization. It does not rewrite text.

## Domain contract

```dart
abstract interface class TranscriptRefiner {
  Future<TranscriptRefinement> refine(TranscriptRefinementRequest request);
}

final class TranscriptRefinementRequest {
  final String rawTranscript;
  final String locale;
  final List<String> protectedVocabulary;
  final Duration deadline;
}

final class TranscriptRefinement {
  final String rawTranscript;
  final String? proposedTranscript;
  final String selectedTranscript;
  final TranscriptRefinementStatus status;
  final List<TranscriptEdit> edits;
  final List<TranscriptRejectionReason> rejectionReasons;
  final String refinerId;
  final String refinerVersion;
  final Duration elapsed;
}
```

Statuses are `unchanged`, `applied`, `rejected`, `timedOut`, and `failed`.
`selectedTranscript` equals the proposal only for `applied`; every other
status selects the exact raw transcript. All collections are immutable.

An edit records raw grapheme start/end indexes, replacement text, and one of
`whitespace`, `punctuation`, or `vocabulary`. It does not store byte offsets.

## Deterministic production stage

The first implementation performs these operations in order:

1. trim leading and trailing whitespace;
2. collapse internal Unicode whitespace to one ordinary space only between
   Latin tokens; remove whitespace between adjacent CJK graphemes;
3. replace a case-insensitive whole Latin token when it uniquely matches one
   configured protected-vocabulary token, for example `flutter` → `Flutter`;
4. preserve every other grapheme exactly.

It does not add sentence punctuation, remove fillers, convert Simplified and
Traditional Chinese, normalize numbers, or replace homophones. Those changes
need stronger linguistic evidence than deterministic rules have.

The refiner returns `unchanged` when selected output equals raw output and
`applied` otherwise. Its normal execution is synchronous behind the async
interface and should finish below 5 ms for a 500-grapheme utterance.

## Proposal safety gate

All future proposal providers, including a local LLM, pass through one pure
gate before their text can be selected.

The gate compares normalized protected tokens extracted from raw and proposal:

- Arabic and full-width number sequences, decimals, percentages, currency
  amounts, dates, times, and semantic version strings;
- Taiwan Mandarin negation tokens: `不`, `沒`, `沒有`, `不是`, `別`, `不要`,
  `未`, and `無`;
- URLs and email addresses;
- case-insensitive whole tokens from `protectedVocabulary`.

The multisets must be equal. Token order must also remain equal for numbers,
negation, URLs, and email addresses. A proposal is rejected if it is empty,
adds text to an empty raw transcript, exceeds a grapheme edit ratio of 0.20,
or changes protected evidence. Rejection reasons name token categories and
counts but never contain the private token values.

The 0.20 edit ratio is an initial safety ceiling, not a quality target. Golden
evaluation may lower it; increasing it requires a new reviewed decision.

## Local-LLM shadow stage

The proposal prompt is fixed and contains only the current finalized
utterance, locale, and protected vocabulary needed for that utterance. It does
not receive conversation history, memory, the agent profile, or previous raw
transcripts.

The model is instructed to return JSON containing only `refinedTranscript`.
Its allowed changes are punctuation, obvious recognition spelling, and
configured vocabulary casing. It must preserve fillers, self-corrections,
numbers, negation, entities, and language.

Initially the local-LLM stage is shadow-only:

- Lulo submits the deterministic result immediately;
- the proposal may complete later and is scored as a candidate artifact;
- it cannot change the active conversation or visible transcript;
- cancellation drops the request when the voice session or app is disposed.

It can become selectable only after a separate decision confirms all of these
gates on the private golden corpus:

- zero protected-token violations;
- no case with worse spoken CER than raw;
- aggregate literal CER no worse than the deterministic stage;
- p95 completion at or below 250 ms on the target Mac;
- manual review finds no meaning-changing edit.

## Deadline and failure behavior

The `VoiceConversationController` gives an active refiner 250 ms from receipt
of a final transcript. On timeout, exception, malformed result, or controller
disposal it submits raw text. Refinement never blocks partial display,
barge-in, native endpoint finalization, or stopping speech.

Only one final utterance is refined at a time per controller. Push-to-talk
collects all final fragments first, joins them using the existing behavior,
then performs one refinement on the complete held utterance.

If a previous answer is still winding down, the pending utterance stores the
whole `TranscriptRefinement`, not only selected text, so the raw value survives
the wait.

## Persistence and reversibility

Conversation storage gains optional voice-input provenance associated with a
user turn:

```text
raw_transcript
refined_transcript
refinement_status
refiner_id
refiner_version
refinement_edits_json
```

Typed messages leave these fields null. Voice turns always store
`raw_transcript`; `refined_transcript` is non-null only when a proposal was
applied. The existing user-turn text stores `selectedTranscript` so current UI
and inference behavior remain compatible.

`ConversationDatabase.schemaVersion` advances from `1` to `2`. Its `onUpgrade`
path adds the six nullable columns only when upgrading from version `1`;
fresh databases create them with the table. The generated Drift file is
regenerated from the table definition and is not hand-edited.

The migration is additive and nullable. Existing rows remain valid. Storage
must write the user turn and its provenance in one transaction; it must never
persist a polished turn without its raw source. A future UI can reveal or
restore the raw version without another migration.

Logs may contain status, elapsed milliseconds, edit count, refiner ID, and
stable conversation/turn IDs. They never contain raw text, proposed text,
replacement text, or protected token values.

## Evaluation artifacts

A development-only recorder converts a list of refinements to the existing
transcript candidate envelope:

```json
{
  "kind": "transcript",
  "runId": "deterministic-refiner-v1",
  "adapter": {"name": "lulo-deterministic-refiner", "version": "1"},
  "cases": [
    {
      "caseId": "code-switch-product-names",
      "rawTranscript": "我用 flutter 跟 mlx",
      "refinedTranscript": "我用 Flutter 跟 MLX",
      "partialEvents": [],
      "finalAtMs": 0
    }
  ]
}
```

The artifact is written only by an explicit development command to a
caller-selected directory. Production does not continuously export private
transcripts.

## Testing strategy

Red/Green tests cover:

1. conservative Taiwan Mandarin whitespace handling;
2. whole-token, case-insensitive vocabulary correction;
3. substring collisions such as `ML` inside `HTML`;
4. immutable raw, proposal, selected text, edits, and rejection reasons;
5. number, negation, URL, email, vocabulary, empty, and edit-ratio rejection;
6. reason metadata that does not reveal protected values;
7. timeout, exception, cancellation, and raw fallback;
8. final transcript and complete push-to-talk refinement exactly once;
9. pending utterances retaining provenance;
10. additive storage migration and atomic raw/refined persistence;
11. typed turns leaving voice provenance null;
12. evaluation export matching the voice-eval candidate contract.

The root verifier must remain green. Local-LLM shadow tests use a fake proposal
provider and never load a model.

## Delivery order

1. Pure refinement values, deterministic rules, and proposal safety gate.
2. Deadline-bound app orchestration and voice-controller integration.
3. Additive conversation persistence for voice provenance.
4. Development-only voice-eval candidate export.
5. Local-LLM proposal provider in shadow mode as its own follow-up slice.
