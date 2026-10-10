# Reversible Transcript Refiner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refine finalized Taiwan Mandarin transcripts conservatively while preserving raw text, edit provenance, and immediate fallback.

**Architecture:** Pure immutable policy and safety gates live in `agent_core`; the Flutter app supplies configured vocabulary and a deadline-bound orchestrator. Voice submission carries a typed refinement through the conversation pipeline, and Drift persists nullable provenance atomically with the selected user turn.

**Tech Stack:** Dart 3, Flutter, Drift/SQLite, `characters`, `test`, `flutter_test`.

## Global Constraints

- Work in this repository on the user-approved `main` branch.
- Never refine partial transcripts.
- Never log raw, proposed, selected, replacement, or protected-token text.
- Any timeout, exception, invalid proposal, or disposal submits exact raw text.
- Production deterministic refinement must not load a model or use a network.
- Local-LLM proposals remain shadow-only in this plan.
- Follow Red/Green TDD for every behavioral change.

---

### Task 1: Pure deterministic refiner and safety gate

**Files:**
- Create: `packages/agent_core/lib/src/transcript_refiner/transcript_refinement.dart`
- Create: `packages/agent_core/lib/src/transcript_refiner/deterministic_transcript_refiner.dart`
- Create: `packages/agent_core/lib/src/transcript_refiner/transcript_proposal_gate.dart`
- Create: `packages/agent_core/test/transcript_refinement_test.dart`
- Create: `packages/agent_core/test/deterministic_transcript_refiner_test.dart`
- Create: `packages/agent_core/test/transcript_proposal_gate_test.dart`
- Modify: `packages/agent_core/lib/agent_core.dart`
- Modify: `packages/agent_core/pubspec.yaml`

**Interfaces:**
- Produces immutable `TranscriptRefinementRequest`, `TranscriptRefinement`, `TranscriptEdit`, statuses, edit kinds, and rejection reasons.
- Produces `TranscriptRefiner.refine(request)` and `DeterministicTranscriptRefiner`.
- Produces `TranscriptProposalGate.evaluate(raw, proposal, protectedVocabulary)`.

- [ ] Write one failing test per immutable value and deterministic whitespace/vocabulary behavior.
- [ ] Run focused tests and confirm RED because the types do not exist.
- [ ] Implement only trimming, safe CJK/Latin whitespace, and whole-token configured vocabulary casing.
- [ ] Run focused tests and confirm GREEN.
- [ ] Write failing safety tests for empty proposals, numbers, full-width numbers, negation, URL, email, vocabulary, order, and edit ratio `> 0.20`.
- [ ] Run the gate test and confirm RED.
- [ ] Implement grapheme-aware protected-token comparison and redacted reasons.
- [ ] Run all core tests and strict analysis.
- [ ] Commit: `feat(agent): refine transcripts conservatively`

### Task 2: Deadline-bound app orchestration

**Files:**
- Create: `apps/local_agent_macos/lib/features/transcript_refiner/deadline_transcript_refiner.dart`
- Create: `apps/local_agent_macos/test/features/transcript_refiner/deadline_transcript_refiner_test.dart`
- Modify: `apps/local_agent_macos/lib/app/bootstrap.dart`

**Interfaces:**
- Produces `DeadlineTranscriptRefiner` wrapping any `TranscriptRefiner` with a 250 ms deadline and raw fallback.
- Bootstrap injects the deterministic refiner and vocabulary from `AgentContextProvider` without exposing profile memory.

- [ ] Write failing timeout, exception, success, and disposal tests using controllable completers.
- [ ] Run focused tests and confirm RED.
- [ ] Implement the minimal wrapper with one in-flight request and safe fallback statuses.
- [ ] Run focused tests and strict Flutter analysis.
- [ ] Commit: `feat(voice): bound transcript refinement latency`

### Task 3: Final and held voice integration

**Files:**
- Modify: `apps/local_agent_macos/lib/features/voice/voice_conversation_controller.dart`
- Modify: `apps/local_agent_macos/test/features/voice/voice_conversation_controller_test.dart`
- Modify: `apps/local_agent_macos/lib/app/app_composition.dart`
- Modify: `apps/local_agent_macos/lib/app/bootstrap.dart`

**Interfaces:**
- Controller accepts a `TranscriptRefiner` and retains `TranscriptRefinement?` for a pending utterance.
- Final transcripts refine exactly once before submit; held fragments join first and refine once.

- [ ] Write a failing ordinary-final test proving selected text submits and raw remains in provenance.
- [ ] Run the focused test and confirm RED.
- [ ] Implement async final refinement with stale-session/disposal fencing.
- [ ] Write failing tests for timeout fallback, pending-answer wait, empty final, and complete push-to-talk refinement once.
- [ ] Run each focused test to confirm RED before its implementation.
- [ ] Implement minimal pending and push-to-talk behavior without touching partial handling.
- [ ] Run the complete voice-controller suite and Flutter analysis.
- [ ] Commit: `feat(voice): refine finalized utterances`

### Task 4: Additive conversation provenance storage

**Files:**
- Modify: `packages/agent_core/lib/src/conversation/turn.dart`
- Modify: `packages/agent_core/test/conversation_contract_test.dart`
- Modify: `apps/local_agent_macos/lib/features/conversation/conversation_storage_service.dart`
- Modify: `apps/local_agent_macos/lib/features/conversation/drift_conversation_storage_service.dart`
- Regenerate: `apps/local_agent_macos/lib/features/conversation/drift_conversation_storage_service.g.dart`
- Modify: `apps/local_agent_macos/test/features/conversation/drift_conversation_storage_service_test.dart`
- Modify: repository/view-model/controller tests and fakes that construct or save user turns.

**Interfaces:**
- `Turn` gains optional immutable `VoiceInputProvenance` for completed user turns only.
- Drift schema advances from `1` to `2` with six nullable columns.
- Schema-1 upgrades add every column; fresh schema-2 databases create them directly.

- [ ] Write failing core invariants for typed turns, voice turns, raw/refined consistency, and immutability.
- [ ] Run core focused tests and confirm RED.
- [ ] Add `VoiceInputProvenance` and optional `Turn.voiceInput`.
- [ ] Write failing Drift round-trip and schema-1 migration tests.
- [ ] Run focused storage tests and confirm RED.
- [ ] Add nullable columns and `onUpgrade`, then regenerate Drift code with the repository's build command.
- [ ] Thread provenance through `ConversationRepository.startGeneration` without changing inference text.
- [ ] Run core, storage, repository, view-model, and voice tests plus strict analyses.
- [ ] Commit: `feat(conversation): persist voice refinement provenance`

### Task 5: Evaluation export and full verification

**Files:**
- Create: `apps/local_agent_macos/lib/features/transcript_refiner/transcript_candidate_export.dart`
- Create: `apps/local_agent_macos/test/features/transcript_refiner/transcript_candidate_export_test.dart`
- Modify: `docs/features/voice.md`
- Modify: `docs/README.md`

**Interfaces:**
- Produces the existing voice-eval transcript candidate schema from explicitly supplied case IDs and refinement results.
- Export writes only to a caller-selected path and is never invoked by production startup.

- [ ] Write a failing export test pinning raw/refined separation, adapter metadata, stable case order, and no automatic filesystem write.
- [ ] Run focused test and confirm RED.
- [ ] Implement the pure JSON export builder and document the explicit development workflow.
- [ ] Run all affected focused tests and strict analyses.
- [ ] Run `dart run tool/verify.dart` from the repository root and require exit `0`.
- [ ] Commit: `feat(voice-eval): export transcript refinements`
