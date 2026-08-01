# Taiwan Mandarin Voice Evaluation Harness Design

## Summary

Lulo needs one repeatable local evaluation contract before changing its ASR,
transcript refinement, endpointing, prosody chunking, or TTS model. The first
version adds a provider-neutral benchmark under the main repository. It keeps
source audio and raw outputs immutable, evaluates every experimental stage as
a named candidate, and produces machine-readable results plus a concise human
review sheet.

The harness is offline-first. It may call Lulo's existing localhost sidecars,
but it must not upload audio, transcripts, metrics, or personal metadata.

## Goals

1. Version a compact Taiwan Mandarin corpus contract that can grow without
   changing evaluator code.
2. Measure ASR accuracy, transcript refinement, endpoint decisions, and TTS
   timing through independent adapters.
3. Preserve raw evidence so every transformed transcript or timing decision is
   reversible and attributable.
4. Give Qwen prosody experiments and Pipecat Smart Turn shadow evaluation the
   same baseline, case IDs, and report format.
5. Run deterministic unit tests without loading speech or language models.

## Non-goals

- Choosing a replacement TTS model.
- Automatically recording the user or shipping personal audio in Git.
- Letting Smart Turn control the production endpoint.
- Automatically rewriting production transcripts.
- Computing perceptual voice quality from an opaque neural scorer.
- Building the future public settings UI.

## Repository boundary

The benchmark lives at `benchmarks/voice_eval/` in the main
`flutter_local_agent` repository. This is the only repository changed in this
slice.

The existing `~/dev/lulo-tts` sidecar remains an external system under test.
The harness can call its localhost `/render` route, but it does not import the
sidecar's Python modules, edit its files, or depend on its virtual environment.
The same rule applies to the local ASR service.

## Corpus layout

```text
benchmarks/voice_eval/
  README.md
  pubspec.yaml
  corpus/
    zh-TW-v1.json
    audio/
      .gitkeep
  lib/
    voice_eval.dart
    src/
      corpus.dart
      text_normalizer.dart
      transcript_metrics.dart
      turn_metrics.dart
      evaluation_report.dart
  test/
  tool/
    evaluate.dart
```

Audio is deliberately not committed in version one. The manifest stores a
repository-relative audio path, while `.gitignore` excludes files below
`corpus/audio/`. A developer can keep private recordings at those paths. A
case without audio remains valid corpus metadata and is reported as `missing`,
not silently omitted.

## Corpus schema

The manifest is UTF-8 JSON with this top-level shape:

```json
{
  "schemaVersion": 1,
  "corpusId": "zh-TW-v1",
  "locale": "zh-TW",
  "cases": []
}
```

Each case contains:

```json
{
  "id": "code-switch-product-names",
  "category": "code_switching",
  "prompt": "我剛剛把 Flutter 跟 MLX 的版本都更新了",
  "expectedTranscript": "我剛剛把 Flutter 跟 MLX 的版本都更新了",
  "audioPath": "audio/code-switch-product-names.wav",
  "tags": ["english", "product-name"],
  "expectedPausesMs": [],
  "notes": "English product names inside Taiwan Mandarin."
}
```

Required case fields are `id`, `category`, `prompt`, `expectedTranscript`,
`audioPath`, and `tags`. IDs are unique stable kebab-case identifiers. Paths
must be relative, must remain below `corpus/audio/`, and must end in `.wav`.
Unknown fields are ignored for forward compatibility; invalid cases fail the
manifest load with the case ID and field name.

The initial corpus contains at least twelve scripts across these categories:

- `short_answer`: acknowledgements and conversational fragments;
- `code_switching`: English product names and abbreviations in Mandarin;
- `numbers`: dates, time, money, percentages, and model versions;
- `disfluency`: fillers, repetitions, and self-corrections;
- `punctuation`: clauses whose written punctuation should not become unnatural
  spoken pauses;
- `long_form`: multi-clause requests with meaningful internal pauses;
- `barge_in`: an utterance that begins while Lulo is speaking;
- `endpoint`: incomplete thoughts and questions with a long thinking pause.

The corpus text uses Taiwan Traditional Chinese vocabulary and orthography.
It does not attempt to encode a phonetic accent label as ground truth.

## Input artifacts

One evaluation run has a stable `runId`, UTC timestamp, adapter name, adapter
version, corpus ID, and one result per requested case. Candidate artifacts are
JSON files under a caller-selected output directory, never inside the corpus.
Every candidate file uses this envelope:

```json
{
  "schemaVersion": 1,
  "kind": "transcript",
  "runId": "2026-08-02-apple-speech-baseline",
  "adapter": {"name": "apple-speech", "version": "macOS-27"},
  "corpusId": "zh-TW-v1",
  "cases": []
}
```

`kind` is `transcript`, `turn`, or `tts`, and determines the schema of each
object in `cases`. The pair of `kind` and `runId` is unique within one report.

### Transcript candidate

```json
{
  "caseId": "code-switch-product-names",
  "rawTranscript": "我剛剛把 flutter 跟 mlx 的版本都更新了",
  "refinedTranscript": "我剛剛把 Flutter 跟 MLX 的版本都更新了",
  "partialEvents": [
    {"atMs": 420, "text": "我剛剛"}
  ],
  "finalAtMs": 2380
}
```

`rawTranscript` is mandatory. `refinedTranscript` is optional and can never
replace the raw value. Partial events retain monotonic milliseconds from the
start of the source audio.

### Turn candidate

```json
{
  "caseId": "endpoint-thinking-pause",
  "speechSegments": [{"startMs": 0, "endMs": 940}],
  "baselineSubmitAtMs": 1740,
  "candidateSubmitAtMs": 1320,
  "expectedSubmitWindowMs": {"start": 1200, "end": 1800}
}
```

The baseline is today's Lulo endpoint. A shadow candidate records what another
detector would have done, but never invokes `finalize` and never changes the
live conversation.

### TTS candidate

```json
{
  "caseId": "punctuation-natural-clauses",
  "text": "先回答核心，細節我等等再補。",
  "voice": "ryan",
  "adapter": "qwen3-base-8bit",
  "requestStartedAtMs": 0,
  "firstAudioAtMs": 430,
  "completedAtMs": 3180,
  "audioDurationMs": 2740,
  "audioPath": "artifacts/punctuation-natural-clauses.wav"
}
```

Generated audio belongs to the run output directory and is never treated as
human ground truth.

## Text normalization and transcript metrics

The evaluator reports two character error rates:

1. `literalCer`: Unicode-normalized text after trimming and collapsing
   whitespace. Letter case and punctuation remain significant.
2. `spokenCer`: the same text with Unicode punctuation, whitespace, and ASCII
   letter case removed. Traditional and Simplified Chinese are not converted.

Both use Unicode grapheme clusters rather than UTF-16 code units. The report
also includes substitution, deletion, and insertion counts from the same
minimum edit path. Empty reference behavior is explicit: two empty strings
score zero; a non-empty candidate against an empty reference scores one with
all candidate graphemes counted as insertions.

Raw and refined transcripts are scored independently. A refiner report must
therefore show whether refinement improved spoken CER and whether it changed
literal CER, rather than presenting only the polished output.

## Turn metrics

For each turn candidate the evaluator classifies the candidate submission:

- `early` when it precedes the expected window;
- `within_window` when it is inclusive of the start and end;
- `late` when it follows the expected window;
- `missing` when no candidate decision exists.

It reports candidate latency from the final speech segment's end, delta from
the baseline decision, and corpus-level early, within-window, late, and missing
counts. Negative latency is allowed as evidence of a premature decision and is
classified as early when outside the expected window.

This version does not synthesize VAD decisions from WAV samples. It evaluates
timestamp evidence emitted by the production baseline and future shadow
adapters, keeping signal processing out of the portable scoring core.

## TTS timing and human review

The automated TTS report contains first-audio latency, synthesis completion
latency, audio duration, real-time factor, and missing/failed status per case.
The harness does not claim these metrics measure naturalness.

Naturalness uses a manual blind review sheet generated from candidate files.
Each clip is assigned an opaque randomized label. The reviewer scores one to
five for:

- Taiwan Mandarin naturalness;
- voice identity consistency;
- pacing and pause placement;
- intelligibility;
- listening preference.

The mapping from opaque label to adapter is stored separately so the review
can be completed before revealing the model. The first version exports the
review sheet but does not build a review UI.

## Report contract

The CLI accepts a corpus manifest and zero or more candidate artifact files.
It writes:

- `report.json`: complete machine-readable inputs, metrics, statuses, tool
  version, and deterministic corpus summary;
- `summary.md`: short comparison table, regressions, missing evidence, and no
  raw private transcript text;
- `review.json`: opaque randomized clip labels and scoring fields when TTS
  candidates are present;
- `review-key.json`: the separate opaque-label-to-adapter mapping, generated
  beside the review sheet and not needed until scoring is complete.

The command exits non-zero only for an invalid manifest, invalid candidate
schema, duplicate candidate identity, or write failure. Missing private audio
and absent optional candidate stages remain visible statuses and do not make a
metadata-only run fail. A `--require-audio` flag converts missing audio into a
validation failure for real benchmark runs.

Reports never include absolute home-directory paths. Paths are relative to the
corpus or output root, and error messages redact the home prefix.

## CLI

The initial interface is:

```text
dart run tool/evaluate.dart \
  --corpus corpus/zh-TW-v1.json \
  --candidate path/to/candidate.json \
  --output path/to/run-directory \
  [--require-audio]
```

With no candidates, it validates the corpus and creates a baseline inventory
report. Multiple candidate files are evaluated together when their adapter
and run labels are unique.

## Error handling

- Schema errors name the JSON file, case ID when available, and invalid field.
- A malformed case or candidate fails the whole run; partial scoring would make
  comparisons look complete when they are not.
- Missing audio is a first-class status unless `--require-audio` is set.
- Metric computation never mutates the decoded input objects.
- Existing output directories are rejected instead of overwritten.
- No evaluator log contains transcript or prompt content by default.

## Testing strategy

The package is pure Dart and has no Flutter, native, model, or network
dependency. Red/Green tests cover:

1. strict manifest validation, duplicate IDs, and safe relative WAV paths;
2. Taiwan Traditional Chinese, Latin case, punctuation, empty strings, and
   grapheme-cluster edit accounting;
3. raw versus refined transcript scoring without overwriting raw evidence;
4. early, inclusive-window, late, missing, and negative endpoint latency;
5. deterministic aggregate and stable JSON ordering;
6. path redaction and refusal to overwrite an existing run directory;
7. metadata-only success and `--require-audio` failure;
8. deterministic blind labels with a supplied seed.

The repository verifier adds format, analysis, and this package's tests. No
test requires the personal audio corpus or running sidecars.

## Privacy and provenance

- Human recordings and generated audio are ignored by Git by default.
- Corpus scripts and expected transcripts must not contain secrets or private
  conversation history.
- Each run records adapter and corpus versions, but no machine username,
  hostname, microphone name, or absolute path.
- A future opt-in export must be designed separately; this slice has none.
- Deleting a run directory removes its candidates, generated clips, and report
  without affecting the immutable private source audio.

## Delivery order

1. Corpus schema, loader, and the initial twelve Taiwan Mandarin scripts.
2. Normalization and transcript metrics.
3. Turn-window metrics.
4. Stable reports and blind TTS review ordering.
5. CLI, documentation, and repository verifier integration.

The Qwen reference-corpus runner, reversible transcript refiner, and Pipecat
Smart Turn v3 adapter remain separate implementation slices built against this
contract.
