# Taiwan Mandarin Voice Evaluation Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a deterministic local benchmark that compares Taiwan Mandarin transcripts, turn boundaries, and TTS timing without loading a model or exposing private audio.

**Architecture:** A standalone pure-Dart package owns immutable corpus/candidate contracts, scoring, and reports. The CLI reads versioned JSON and local WAV paths, then writes a new run directory; later Qwen, refiner, and Smart Turn adapters produce candidate JSON against the same contract.

**Tech Stack:** Dart 3, `characters`, `args`, `path`, `test`, JSON, Markdown.

## Global Constraints

- Work only in this repository on the user-approved `main` branch.
- Do not modify the dirty external `~/dev/lulo-tts` repository.
- Do not commit human or generated audio.
- Do not log transcript or prompt content by default.
- Preserve raw transcripts and score refined transcripts independently.
- Follow Red/Green TDD for every behavioral change.

---

### Task 1: Corpus contract and Taiwan Mandarin manifest

**Files:**
- Create: `benchmarks/voice_eval/pubspec.yaml`
- Create: `benchmarks/voice_eval/lib/voice_eval.dart`
- Create: `benchmarks/voice_eval/lib/src/corpus.dart`
- Create: `benchmarks/voice_eval/test/corpus_test.dart`
- Create: `benchmarks/voice_eval/corpus/zh-TW-v1.json`
- Create: `benchmarks/voice_eval/corpus/audio/.gitignore`

**Interfaces:**
- Produces: `VoiceCorpus.fromJson(Map<String, Object?>, {required String source})`
- Produces: `VoiceEvalCase` with stable ID, category, prompt, expected transcript, safe relative WAV path, tags, expected pauses, and notes.

- [ ] **Step 1: Write failing loader tests**

Test a valid manifest, duplicate IDs, missing fields, non-kebab IDs, absolute/traversing paths, non-WAV paths, and missing audio status without reading transcript content into diagnostics.

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `dart test test/corpus_test.dart`
Expected: FAIL because `VoiceCorpus` does not exist.

- [ ] **Step 3: Implement the minimal immutable corpus types and validation**

Use typed final fields, defensive list copies, schema version `1`, and errors shaped as `FormatException('<source>: case <id>: invalid <field>')`.

- [ ] **Step 4: Add the twelve-script `zh-TW-v1` manifest and audio ignore rule**

Cover short answers, code switching, numbers, disfluency, punctuation, long form, barge-in, and endpoint thinking pauses. Keep scripts synthetic and non-private.

- [ ] **Step 5: Run focused tests and analysis, then commit**

Run: `dart test test/corpus_test.dart && dart analyze --fatal-infos --fatal-warnings`
Commit: `feat(voice-eval): define Taiwan Mandarin corpus`

### Task 2: Grapheme-aware transcript metrics

**Files:**
- Create: `benchmarks/voice_eval/lib/src/text_normalizer.dart`
- Create: `benchmarks/voice_eval/lib/src/transcript_metrics.dart`
- Create: `benchmarks/voice_eval/test/transcript_metrics_test.dart`
- Modify: `benchmarks/voice_eval/lib/voice_eval.dart`

**Interfaces:**
- Produces: `normalizeLiteral(String)` and `normalizeSpoken(String)`.
- Produces: `TranscriptScore scoreTranscript({required String reference, required String candidate})`.
- Produces: `TranscriptComparison` containing independent raw and optional refined scores.

- [ ] **Step 1: Write failing normalization and edit-distance tests**

Pin Traditional Chinese, Latin case, Unicode punctuation, whitespace,
emoji/grapheme clusters, substitutions, insertions, deletions, and both empty-reference cases.

- [ ] **Step 2: Run focused tests and confirm RED**

Run: `dart test test/transcript_metrics_test.dart`
Expected: FAIL because the normalization and scoring APIs do not exist.

- [ ] **Step 3: Implement literal/spoken normalization and Levenshtein backtracking**

Normalize to NFC-compatible Dart text behavior, operate on `Characters`, use a deterministic substitution-before-deletion-before-insertion tie break, and return counts plus CER.

- [ ] **Step 4: Add independent raw/refined comparison**

Require raw text; allow refined text to be absent; never mutate or replace raw evidence.

- [ ] **Step 5: Run package tests and analysis, then commit**

Run: `dart test && dart analyze --fatal-infos --fatal-warnings`
Commit: `feat(voice-eval): score transcript candidates`

### Task 3: Shadow turn metrics

**Files:**
- Create: `benchmarks/voice_eval/lib/src/turn_metrics.dart`
- Create: `benchmarks/voice_eval/test/turn_metrics_test.dart`
- Modify: `benchmarks/voice_eval/lib/voice_eval.dart`

**Interfaces:**
- Produces: `TurnCandidate`, `SubmitWindow`, `TurnScore`, `TurnClassification`.
- Produces: `scoreTurn(TurnCandidate)` and `summarizeTurns(Iterable<TurnScore>)`.

- [ ] **Step 1: Write failing boundary tests**

Test early, inclusive start/end, late, missing, negative latency, baseline delta, and aggregate counts.

- [ ] **Step 2: Run focused tests and confirm RED**

Run: `dart test test/turn_metrics_test.dart`
Expected: FAIL because turn metric types do not exist.

- [ ] **Step 3: Implement pure timestamp scoring**

Validate ordered speech segments and windows, compute latency from the final speech end, allow negative candidate latency as evidence, and never invoke an endpoint callback.

- [ ] **Step 4: Run package tests and analysis, then commit**

Run: `dart test && dart analyze --fatal-infos --fatal-warnings`
Commit: `feat(voice-eval): score shadow turn decisions`

### Task 4: Candidate envelopes and deterministic reports

**Files:**
- Create: `benchmarks/voice_eval/lib/src/candidate.dart`
- Create: `benchmarks/voice_eval/lib/src/evaluation_report.dart`
- Create: `benchmarks/voice_eval/test/candidate_test.dart`
- Create: `benchmarks/voice_eval/test/evaluation_report_test.dart`
- Modify: `benchmarks/voice_eval/lib/voice_eval.dart`

**Interfaces:**
- Produces: `CandidateRun.fromJson(...)` for transcript, turn, and TTS kinds.
- Produces: `VoiceEvaluation.evaluate(...)`.
- Produces: `EvaluationReport.toJson()`, `toSummaryMarkdown()`, and deterministic blind-review artifacts with a caller-supplied seed.

- [ ] **Step 1: Write failing candidate validation tests**

Pin schema version, kind-specific case bodies, corpus ID, unique `(kind, runId)`, monotonic partial timestamps, and relative artifact paths.

- [ ] **Step 2: Run focused test and confirm RED**

Run: `dart test test/candidate_test.dart`
Expected: FAIL because candidate contracts do not exist.

- [ ] **Step 3: Implement candidate decoding and validation**

Decode all three kinds into immutable values and retain raw values without logging transcript content.

- [ ] **Step 4: Write failing report tests**

Pin stable case ordering, transcript and turn aggregates, TTS first-audio/RTF values, missing statuses, summary privacy, deterministic opaque labels, and separate review key.

- [ ] **Step 5: Run focused report test and confirm RED**

Run: `dart test test/evaluation_report_test.dart`
Expected: FAIL because report generation does not exist.

- [ ] **Step 6: Implement minimal report and blind review generation**

Use sorted map insertion order, derive opaque labels from a seeded shuffle, omit transcript content from Markdown, and keep adapter mapping only in `review-key.json` data.

- [ ] **Step 7: Run package tests and analysis, then commit**

Run: `dart test && dart analyze --fatal-infos --fatal-warnings`
Commit: `feat(voice-eval): report comparable voice runs`

### Task 5: CLI, docs, and repository gate

**Files:**
- Create: `benchmarks/voice_eval/tool/evaluate.dart`
- Create: `benchmarks/voice_eval/test/cli_test.dart`
- Create: `benchmarks/voice_eval/README.md`
- Modify: `tool/verify.dart`
- Modify: `docs/README.md`

**Interfaces:**
- Produces CLI flags `--corpus`, repeatable `--candidate`, `--output`, and `--require-audio`.
- Adds voice-eval format, analysis, and tests to the root verifier.

- [ ] **Step 1: Write failing CLI process tests**

Test metadata-only success, invalid manifest failure, missing audio tolerance, `--require-audio` failure, home-path redaction, and refusal to overwrite an existing output directory.

- [ ] **Step 2: Run focused CLI tests and confirm RED**

Run: `dart test test/cli_test.dart`
Expected: FAIL because `tool/evaluate.dart` does not exist.

- [ ] **Step 3: Implement the CLI and atomic new-directory output**

Parse flags with `args`, load JSON without printing source text, validate audio with resolved paths constrained below corpus audio root, and write `report.json`, `summary.md`, plus review files when present.

- [ ] **Step 4: Document private-audio setup and example commands**

Explain what is and is not measured, WAV placement, candidate schema, metadata-only mode, and that Smart Turn remains shadow-only.

- [ ] **Step 5: Add package verification to the root gate**

Run voice-eval `dart format --set-exit-if-changed .`, `dart analyze --fatal-infos --fatal-warnings`, and `dart test` from its package directory.

- [ ] **Step 6: Run focused and full verification**

Run: `cd benchmarks/voice_eval && dart pub get && dart test && dart analyze --fatal-infos --fatal-warnings`
Run: `dart run tool/verify.dart` (from the repository root)
Expected: every subprocess exits `0`; real-model smoke tests may retain their documented environment-dependent skips.

- [ ] **Step 7: Commit the completed integration**

Commit: `feat(voice-eval): add local evaluation harness`
