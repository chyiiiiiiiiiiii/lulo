# Qwen Transcript Shadow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a disabled-by-default, loopback-only Qwen transcript proposal path that produces evaluation evidence without affecting Lulo's live conversation.

**Architecture:** Provider-independent immutable values live in `agent_core`. The Flutter app owns a single-flight shadow coordinator, optional loopback HTTP provider, bounded evaluation sink, and fire-and-forget voice dispatch; deterministic refinement remains the only live authority.

**Tech Stack:** Dart 3, Flutter, `dart:io` HttpClient, `agent_core`, `flutter_test`, existing `voice_eval` JSON contract.

## Global Constraints

- Work in this repository on the user-approved `main` branch.
- Shadow work never changes selected transcript, UI, conversation storage, inference prompt, endpointing, or TTS.
- Never send conversation history, memories, the full profile, or previous transcripts to a proposal provider.
- Default composition is disabled and performs no request, process launch, download, or file write.
- HTTP is permitted only to literal `127.0.0.1` or `::1`, with no redirects or retries.
- Logs never contain transcript text, proposal text, vocabulary values, URLs, emails, or replacement fragments.
- At most one request is in flight; newer requests are skipped, never queued.
- Follow Red/Green TDD for every behavioral change.

---

### Task 1: Immutable proposal and shadow result contracts

**Files:**
- Create: `packages/agent_core/lib/src/transcript_refiner/transcript_proposal.dart`
- Create: `packages/agent_core/test/transcript_proposal_test.dart`
- Modify: `packages/agent_core/lib/agent_core.dart`

**Interfaces:**
- Produces `TranscriptProposalRequest({requestId, rawTranscript, locale, protectedVocabulary, deadline, caseId})`.
- Produces `TranscriptProposal({requestId, refinedTranscript, providerId, providerVersion, elapsed})`.
- Produces `TranscriptShadowStatus` values `accepted`, `rejected`, `failed`, `timedOut`, and `skippedBusy`.
- Produces `TranscriptShadowResult({request, proposal, gateResult, status, elapsed})`.
- Produces `abstract interface class TranscriptProposalProvider { Future<TranscriptProposal> propose(TranscriptProposalRequest request); }`.

- [ ] **Step 1: Write the failing immutable-value tests**

Test construction, equality, defensive vocabulary copying, non-empty identity fields, accepted-result consistency, and failure results that carry no proposal.

- [ ] **Step 2: Run the test and confirm RED**

Run: `dart test packages/agent_core/test/transcript_proposal_test.dart`

Expected: compilation fails because `TranscriptProposalRequest` and related types do not exist.

- [ ] **Step 3: Implement the minimal contracts and exports**

Use final fields, `List<String>.unmodifiable`, explicit constructor validation, and value equality consistent with existing core types. Do not add I/O or logging.

- [ ] **Step 4: Run core tests and strict analysis**

Run:

```sh
dart test packages/agent_core/test/transcript_proposal_test.dart
dart test packages/agent_core/test
dart analyze packages/agent_core --fatal-infos --fatal-warnings
```

Expected: all exit `0`.

- [ ] **Step 5: Commit**

```sh
git add packages/agent_core/lib/agent_core.dart packages/agent_core/lib/src/transcript_refiner/transcript_proposal.dart packages/agent_core/test/transcript_proposal_test.dart
git commit -m "feat(agent): model transcript shadow evidence"
```

### Task 2: Single-flight shadow coordinator

**Files:**
- Create: `apps/local_agent_macos/lib/features/transcript_refiner/transcript_shadow_coordinator.dart`
- Create: `apps/local_agent_macos/test/features/transcript_refiner/transcript_shadow_coordinator_test.dart`

**Interfaces:**
- Consumes `TranscriptProposalProvider` and `TranscriptProposalGate`.
- Produces `TranscriptShadowCoordinator.submit(TranscriptProposalRequest request)` returning immediately as `void`.
- Produces `TranscriptShadowCoordinator.cancelSession()` and `dispose()`.
- Accepts `FutureOr<void> Function(TranscriptShadowResult result) onResult`.

- [ ] **Step 1: Write a failing non-blocking success test**

Use a `Completer<TranscriptProposal>` provider. Call `submit`, verify the call returns before completing the provider, then complete it and verify one accepted result after the gate.

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `flutter test test/features/transcript_refiner/transcript_shadow_coordinator_test.dart`

Expected: compilation fails because the coordinator does not exist.

- [ ] **Step 3: Implement minimal fire-and-forget coordination**

Capture an epoch per submit, mark the coordinator busy, await the provider in an unawaited private future, gate success, and deliver only when the epoch remains current.

- [ ] **Step 4: Add one failing test at a time for safety rejection, exception, busy skip, cancel-session fencing, sink exception, and disposal**

Each test must assert result status and prove no transcript content is passed to diagnostics. Busy submission emits `skippedBusy` without calling the provider a second time. Cancelled and disposed late completions emit no result.

- [ ] **Step 5: Implement each behavior minimally and keep the suite green**

Provider exceptions become `failed`; proposal request-ID mismatch becomes `failed`; gate rejection becomes `rejected`; sink exceptions are swallowed. No queue is introduced.

- [ ] **Step 6: Run focused tests and strict analysis**

Run:

```sh
flutter test test/features/transcript_refiner/transcript_shadow_coordinator_test.dart
flutter analyze --fatal-infos --fatal-warnings
```

from `apps/local_agent_macos`.

- [ ] **Step 7: Commit**

```sh
git add apps/local_agent_macos/lib/features/transcript_refiner/transcript_shadow_coordinator.dart apps/local_agent_macos/test/features/transcript_refiner/transcript_shadow_coordinator_test.dart
git commit -m "feat(voice): coordinate transcript shadows"
```

### Task 3: Voice dispatch and disabled composition

**Files:**
- Modify: `apps/local_agent_macos/lib/features/voice/voice_conversation_controller.dart`
- Modify: `apps/local_agent_macos/test/features/voice/voice_conversation_controller_test.dart`
- Modify: `apps/local_agent_macos/lib/app/app_composition.dart`
- Modify: `apps/local_agent_macos/lib/app/bootstrap.dart`
- Modify: `apps/local_agent_macos/lib/features/conversation/conversation_view.dart`
- Modify: `apps/local_agent_macos/lib/app/app.dart`
- Modify: `apps/local_agent_macos/test/app/bootstrap_test.dart`

**Interfaces:**
- Controller accepts `TranscriptShadowCoordinator? transcriptShadow`.
- Every non-empty ordinary final and joined held utterance calls `transcriptShadow?.submit(...)` exactly once.
- Request locale is `zh-TW`; vocabulary is the same scoped snapshot used by deterministic refinement.
- Bootstrap passes `null` unless an explicit developer configuration enables a provider.

- [ ] **Step 1: Write a failing ordinary-final dispatch test**

Use a recording shadow seam and a pending provider. Assert the live conversation submits deterministic text without waiting, while shadow receives exact raw text once.

- [ ] **Step 2: Run the single test and confirm RED**

Run the test by exact `--plain-name`; expect constructor/API compilation failure.

- [ ] **Step 3: Add the smallest controller seam and ordinary-final dispatch**

Dispatch from the same final-only method that starts deterministic refinement. Do not alter partial handling or await the shadow.

- [ ] **Step 4: Add failing tests for held speech once, empty final never, disable fencing, and disposal fencing**

The held test must prove fragments are joined before one shadow submit. Existing live-turn assertions remain unchanged.

- [ ] **Step 5: Implement lifecycle forwarding and disabled composition**

Call `cancelSession` when voice disables and `dispose` when the controller disposes. Default constructors pass no shadow coordinator.

- [ ] **Step 6: Run voice, bootstrap, and analysis gates**

Run:

```sh
flutter test test/features/voice/voice_conversation_controller_test.dart
flutter test test/app/bootstrap_test.dart
flutter analyze --fatal-infos --fatal-warnings
```

- [ ] **Step 7: Commit**

```sh
git add apps/local_agent_macos/lib/features/voice/voice_conversation_controller.dart apps/local_agent_macos/test/features/voice/voice_conversation_controller_test.dart apps/local_agent_macos/lib/app/app_composition.dart apps/local_agent_macos/lib/app/bootstrap.dart apps/local_agent_macos/lib/features/conversation/conversation_view.dart apps/local_agent_macos/lib/app/app.dart apps/local_agent_macos/test/app/bootstrap_test.dart
git commit -m "feat(voice): dispatch transcript shadows"
```

### Task 4: Hardened loopback proposal provider

**Files:**
- Create: `apps/local_agent_macos/lib/features/transcript_refiner/loopback_transcript_proposal_provider.dart`
- Create: `apps/local_agent_macos/test/features/transcript_refiner/loopback_transcript_proposal_provider_test.dart`

**Interfaces:**
- Produces `LoopbackTranscriptProposalProvider({required Uri endpoint, HttpClient? client, int maxResponseBytes = 16384})`.
- Implements `TranscriptProposalProvider.propose` with schema version `1` JSON.
- Accepts only literal loopback HTTP endpoints, disables redirects, performs one POST, and closes owned clients on `dispose()`.

- [ ] **Step 1: Write failing constructor tests for remote host, hostname, HTTPS, credentials, query, and fragment**

Accept only `http://127.0.0.1:<port>/<path>` and `http://[::1]:<port>/<path>` with an explicit port and no user info, query, or fragment.

- [ ] **Step 2: Run focused tests and confirm RED**

Run: `flutter test test/features/transcript_refiner/loopback_transcript_proposal_provider_test.dart`

- [ ] **Step 3: Implement endpoint validation without network calls**

Throw `ArgumentError` synchronously for invalid endpoints.

- [ ] **Step 4: Write failing protocol tests against a local `HttpServer`**

Assert schema, request ID, locale, raw transcript, scoped vocabulary, success decoding, non-2xx failure, redirect rejection, mismatched ID, malformed JSON, empty proposal, and response byte ceiling.

- [ ] **Step 5: Implement one POST with bounded streaming decode**

Set JSON content type, `followRedirects = false`, read at most `maxResponseBytes`, require response schema `1`, exact request ID, non-empty provider metadata, and non-empty refined transcript. Never retry.

- [ ] **Step 6: Run provider tests and strict analysis**

Run:

```sh
flutter test test/features/transcript_refiner/loopback_transcript_proposal_provider_test.dart
flutter analyze --fatal-infos --fatal-warnings
```

- [ ] **Step 7: Commit**

```sh
git add apps/local_agent_macos/lib/features/transcript_refiner/loopback_transcript_proposal_provider.dart apps/local_agent_macos/test/features/transcript_refiner/loopback_transcript_proposal_provider_test.dart
git commit -m "feat(voice): add loopback transcript proposals"
```

### Task 5: Bounded evaluation evidence and explicit export

**Files:**
- Create: `apps/local_agent_macos/lib/features/transcript_refiner/transcript_shadow_evidence.dart`
- Create: `apps/local_agent_macos/test/features/transcript_refiner/transcript_shadow_evidence_test.dart`
- Modify: `apps/local_agent_macos/lib/features/transcript_refiner/transcript_candidate_export.dart`
- Modify: `apps/local_agent_macos/test/features/transcript_refiner/transcript_candidate_export_test.dart`
- Modify: `docs/features/voice.md`
- Modify: `benchmarks/voice_eval/README.md`

**Interfaces:**
- Produces a sink with a fixed capacity, transcript-free aggregate counters, optional case-ID evidence, `clear()`, and immutable snapshots.
- Export accepts explicit retained case results and emits the existing candidate schema in stable case-ID order.

- [ ] **Step 1: Write failing bounded-sink tests**

Assert ordinary results update only counters, explicit case results retain at most the configured capacity, oldest evidence is evicted, snapshots are immutable, and `clear()` removes transcript-bearing evidence.

- [ ] **Step 2: Run focused tests and confirm RED**

Run: `flutter test test/features/transcript_refiner/transcript_shadow_evidence_test.dart`

- [ ] **Step 3: Implement the minimal bounded sink**

Use insertion-ordered storage by case ID and immutable snapshot values. Do not write files or log text.

- [ ] **Step 4: Write a failing export bridge test**

Assert accepted Qwen proposals export as `refinedTranscript`, rejected/failed cases retain raw only, adapter metadata is explicit, and case order is stable.

- [ ] **Step 5: Implement export conversion and document the opt-in workflow**

Keep the existing pure builder; add a conversion from explicit evidence snapshot to its `Map<String, TranscriptRefinement>` input without adding filesystem APIs.

- [ ] **Step 6: Run affected tests and strict analyses**

Run:

```sh
flutter test test/features/transcript_refiner
flutter analyze --fatal-infos --fatal-warnings
dart test benchmarks/voice_eval/test
dart analyze benchmarks/voice_eval --fatal-infos --fatal-warnings
```

- [ ] **Step 7: Run the complete repository gate**

Run from repository root: `dart run tool/verify.dart`

Expected: exit `0`; real-model tests may skip only when their documented model paths are absent.

- [ ] **Step 8: Commit**

```sh
git add apps/local_agent_macos/lib/features/transcript_refiner/transcript_shadow_evidence.dart apps/local_agent_macos/test/features/transcript_refiner/transcript_shadow_evidence_test.dart apps/local_agent_macos/lib/features/transcript_refiner/transcript_candidate_export.dart apps/local_agent_macos/test/features/transcript_refiner/transcript_candidate_export_test.dart docs/features/voice.md benchmarks/voice_eval/README.md
git commit -m "feat(voice-eval): retain transcript shadow evidence"
```
