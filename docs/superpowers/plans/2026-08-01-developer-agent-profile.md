# Developer Agent Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Lulo a typed, live-reloadable developer profile that composes a stable Taiwanese Traditional Chinese personality with bounded, relevant structured memories.

**Architecture:** Pure Dart types, memory selection, and prompt composition live in `agent_core`. The macOS app owns JSON persistence and debug/profile file watching through an explicit `AgentContextProvider` injected into `PigeonInferenceService`; the inference adapter never reads files or global state.

**Tech Stack:** Dart 3, Flutter `ChangeNotifier`/`ValueListenable`, `dart:io` `FileSystemEntity.watch`, JSON, existing Pigeon inference boundary, `package:test`, `flutter_test`.

## Global Constraints

- Keep `packages/agent_core` pure Dart with no Flutter or platform imports.
- Follow strict Red/Green TDD and observe every new behavioral test fail for the intended reason before implementation.
- Keep profile-derived prompt content at or below 1,200 Unicode characters.
- Select at most six memories and at most 600 Unicode characters of memory content.
- Never log profile content, memory content, or the composed prompt.
- Never replace built-in behavioral rules with developer-authored instructions.
- Never copy the full conversation archive into the profile context.
- Work on the explicitly approved `main` branch and commit each independently verified task.

---

### Task 1: Agent profile domain and deterministic memory selection

**Files:**
- Create: `packages/agent_core/lib/src/agent_profile/agent_profile.dart`
- Create: `packages/agent_core/lib/src/agent_profile/agent_memory_selector.dart`
- Modify: `packages/agent_core/lib/agent_core.dart`
- Create: `packages/agent_core/test/agent_profile_test.dart`
- Create: `packages/agent_core/test/agent_memory_selector_test.dart`

**Interfaces:**
- Produces: immutable `AgentIdentity`, `AgentPersonality`, `VoiceResponseBehavior`, `AgentMemoryKind`, `AgentMemory`, and `AgentProfile` values.
- Produces: `AgentMemorySelection selectAgentMemories({required AgentProfile profile, required String prompt, int maxEntries = 6, int maxCharacters = 600})`.

- [ ] **Step 1: Write the failing domain tests**

Cover built-in defaults, immutable collections, supported memory kinds, equality, and rejection of empty IDs/content. Name each test after the invalid mutation it catches.

- [ ] **Step 2: Run the domain test and verify RED**

Run: `dart test packages/agent_core/test/agent_profile_test.dart`

Expected: compilation fails because the profile types do not exist.

- [ ] **Step 3: Implement the minimal immutable domain values**

Use const constructors, `List.unmodifiable`, value equality, and a single `AgentProfile.builtIn()` factory whose zh-TW defaults match the approved spec.

- [ ] **Step 4: Run the domain test and verify GREEN**

Run: `dart test packages/agent_core/test/agent_profile_test.dart`

Expected: all tests pass.

- [ ] **Step 5: Write failing selector tests**

Use literal expectations for: disabled removal, triggerless personal/preference eligibility, case-insensitive Latin matching, Chinese substring matching, exact-match ordering, longer-trigger ordering, stable file order, content deduplication, six-entry cap, and 600-character cap.

- [ ] **Step 6: Run the selector test and verify RED**

Run: `dart test packages/agent_core/test/agent_memory_selector_test.dart`

Expected: compilation fails because `selectAgentMemories` does not exist.

- [ ] **Step 7: Implement minimal deterministic selection**

Normalize with `trim().toLowerCase()`, retain each matching trigger length as the score, sort matched entries before triggerless entries, preserve source index for ties, and apply both bounds without cutting a memory in half.

- [ ] **Step 8: Run core tests and verify GREEN**

Run: `dart test packages/agent_core/test`

Expected: all core tests pass.

- [ ] **Step 9: Commit**

```bash
git add packages/agent_core/lib/agent_core.dart packages/agent_core/lib/src/agent_profile packages/agent_core/test/agent_profile_test.dart packages/agent_core/test/agent_memory_selector_test.dart
git commit -m "feat(agent): model structured personal context"
```

### Task 2: Bounded prompt composition

**Files:**
- Create: `packages/agent_core/lib/src/agent_profile/agent_prompt_composer.dart`
- Modify: `packages/agent_core/lib/agent_core.dart`
- Create: `packages/agent_core/test/agent_prompt_composer_test.dart`

**Interfaces:**
- Consumes: `AgentProfile`, `AgentMemorySelection`, and the current user prompt.
- Produces: `AgentPromptContext composeAgentPrompt({required AgentProfile profile, required String prompt, int maxProfileCharacters = 1200})`, containing `instruction`, `selectedMemoryIds`, and `profileCharacterCount`.

- [ ] **Step 1: Write failing composition tests**

Assert observable output behavior with hand-written literals: zh-TW section order, English question behavior, omitted empty sections, question exactly once, selected memory only, stable built-in rules, custom instruction truncation after memory truncation, and the 1,200-character bound.

- [ ] **Step 2: Run the composer test and verify RED**

Run: `dart test packages/agent_core/test/agent_prompt_composer_test.dart`

Expected: compilation fails because the composer does not exist.

- [ ] **Step 3: Implement the minimal composer**

Render the fixed sections `[核心人格]`, `[語音回答方式]`, `[使用者偏好]`, `[與這次問題相關的記憶]`, `[開發者額外指示]`, and `[問題]`; omit empty optional sections; retain the current question outside the profile-character budget.

- [ ] **Step 4: Run core tests and verify GREEN**

Run: `dart test packages/agent_core/test`

Expected: all core tests pass.

- [ ] **Step 5: Refactor only repeated section rendering and rerun**

Run: `dart test packages/agent_core/test`

Expected: all core tests remain green.

- [ ] **Step 6: Commit**

```bash
git add packages/agent_core/lib/agent_core.dart packages/agent_core/lib/src/agent_profile/agent_prompt_composer.dart packages/agent_core/test/agent_prompt_composer_test.dart
git commit -m "feat(agent): compose bounded personal prompts"
```

### Task 3: JSON codec and durable live-reload store

**Files:**
- Create: `apps/local_agent_macos/lib/features/agent_profile/agent_profile_codec.dart`
- Create: `apps/local_agent_macos/lib/features/agent_profile/agent_profile_store.dart`
- Create: `apps/local_agent_macos/test/features/agent_profile/agent_profile_codec_test.dart`
- Create: `apps/local_agent_macos/test/features/agent_profile/agent_profile_store_test.dart`

**Interfaces:**
- Produces: `AgentProfileDecodeResult decodeAgentProfile(Object? json)` with a profile, skipped-memory IDs, or one non-fatal error.
- Produces: `AgentProfileStore` with `AgentProfile get current`, `ValueListenable<int> get revision`, `String? get error`, `Future<void> load()`, and `Future<void> dispose()`.
- Produces: `FileAgentProfileStore({required File file, required bool watch, Duration debounce = const Duration(milliseconds: 250)})`.

- [ ] **Step 1: Write failing codec tests**

Cover the approved JSON example, missing optional fields, unknown fields, unknown enums, invalid root, unsupported schema, individually skipped memories, and unmodifiable decoded collections.

- [ ] **Step 2: Run codec tests and verify RED**

Run: `flutter test test/features/agent_profile/agent_profile_codec_test.dart` from `apps/local_agent_macos`.

Expected: compilation fails because the codec does not exist.

- [ ] **Step 3: Implement the minimal defensive codec**

Decode every field by type, apply built-in defaults, skip malformed memories independently, and never throw for developer-authored input.

- [ ] **Step 4: Run codec tests and verify GREEN**

Run: `flutter test test/features/agent_profile/agent_profile_codec_test.dart`.

Expected: all codec tests pass.

- [ ] **Step 5: Write failing real-filesystem store tests**

Use a temporary directory and real file events. Cover missing file, valid load, malformed initial file, valid change, malformed change retaining last-good state, deletion restoring built-in state, 250 ms debounce, and dispose preventing further revisions.

- [ ] **Step 6: Run store tests and verify RED**

Run: `flutter test test/features/agent_profile/agent_profile_store_test.dart`.

Expected: compilation fails because the store does not exist.

- [ ] **Step 7: Implement the minimal store and watcher**

Watch the parent directory so creating a previously missing profile is observed. Filter events to the exact filename, debounce, load one snapshot, and increment revision only when the effective profile or error changes.

- [ ] **Step 8: Run profile feature tests and verify GREEN**

Run: `flutter test test/features/agent_profile`.

Expected: all profile tests pass without timers or directory handles leaking.

- [ ] **Step 9: Commit**

```bash
git add apps/local_agent_macos/lib/features/agent_profile apps/local_agent_macos/test/features/agent_profile
git commit -m "feat(agent): reload the local developer profile"
```

### Task 4: Inject profile context into local inference

**Files:**
- Modify: `apps/local_agent_macos/lib/features/conversation/pigeon_inference_service.dart`
- Modify: `apps/local_agent_macos/lib/app/bootstrap.dart`
- Modify: `apps/local_agent_macos/lib/app/app_composition.dart`
- Modify: `apps/local_agent_macos/test/features/conversation/pigeon_inference_service_test.dart`
- Modify: `apps/local_agent_macos/test/app/bootstrap_test.dart`

**Interfaces:**
- Produces: `abstract interface class AgentContextProvider { AgentPromptContext compose(String prompt); }` and a profile-backed implementation.
- `PigeonInferenceService` requires an `AgentContextProvider`; each operation captures context immediately before `startGeneration`.

- [ ] **Step 1: Write a failing inference-boundary test**

Assert that the native request contains the configured agent name, user name, voice behavior, one matching memory, no unrelated memory, and the user question exactly once. Also assert native `history` remains the existing bounded turn list rather than profile content.

- [ ] **Step 2: Run the inference test and verify RED**

Run: `flutter test test/features/conversation/pigeon_inference_service_test.dart`.

Expected: the assertion fails because the current request uses only `plainProseInstruction`.

- [ ] **Step 3: Inject and use the provider minimally**

Remove `plainProseInstruction` after its behavior is represented in the built-in composer. Capture one `AgentPromptContext` per operation and send its instruction as `DesktopGenerationRequest.prompt` without logging it.

- [ ] **Step 4: Run the inference test and verify GREEN**

Run: `flutter test test/features/conversation/pigeon_inference_service_test.dart`.

Expected: all inference adapter tests pass.

- [ ] **Step 5: Write failing bootstrap ownership tests**

Assert the durable store path is `Application Support/Lulo/agent_profile.json`, debug/profile watching is selectable for tests, the store is loaded before first generation, and composition disposal closes it exactly once.

- [ ] **Step 6: Run bootstrap tests and verify RED**

Run: `flutter test test/app/bootstrap_test.dart`.

Expected: the new ownership assertions fail because bootstrap does not own a profile store.

- [ ] **Step 7: Wire the store through the composition root**

Construct and load the store during bootstrap, inject its profile-backed provider into every replacement inference service, and dispose it from the app-scoped release callback. Preserve the in-memory built-in provider for previews and tests.

- [ ] **Step 8: Run app and conversation tests and verify GREEN**

Run: `flutter test test/app test/features/conversation/pigeon_inference_service_test.dart`.

Expected: all selected tests pass.

- [ ] **Step 9: Commit**

```bash
git add apps/local_agent_macos/lib/app apps/local_agent_macos/lib/features/conversation/pigeon_inference_service.dart apps/local_agent_macos/test/app/bootstrap_test.dart apps/local_agent_macos/test/features/conversation/pigeon_inference_service_test.dart
git commit -m "feat(agent): inject personal context into every turn"
```

### Task 5: Developer configuration and product documentation

**Files:**
- Create: `docs/features/agent-profile.md`
- Modify: `docs/README.md`
- Modify: `docs/features/settings.md`
- Create outside Git: `~/Library/Application Support/Lulo/agent_profile.json`

**Interfaces:**
- Documents the exact schema, reload semantics, bounds, privacy limitations, and future public settings experience.
- Installs a valid developer profile for Yii without changing tracked defaults for other users.

- [ ] **Step 1: Write the feature documentation**

Include one complete valid JSON example, field meanings, deterministic trigger behavior, error recovery, private-data warning, and editing instructions.

- [ ] **Step 2: Link the feature and record deferred public UX**

Add the profile to `docs/README.md`; record conversational onboarding, memory confirmation cards, scoped memories, sensitive-data exclusions, additional instructions, export, pause, and erase controls in `docs/features/settings.md`.

- [ ] **Step 3: Install Yii's local developer profile**

Create the Application Support directory if absent and write a valid schema-v1 file with `agentName: Lulo`, `userName: Yii`, `locale: zh-TW`, concise warm behavior, the known Lulo project memory, Flutter/MLX/Codex vocabulary, and no speculative personal facts.

- [ ] **Step 4: Verify the JSON and tracked diff**

Run: `python3 -m json.tool "$HOME/Library/Application Support/Lulo/agent_profile.json" >/dev/null && git diff --check`

Expected: exit 0 and no whitespace errors.

- [ ] **Step 5: Run the complete project gate**

Run: `dart run tool/verify.dart`

Expected: every required gate exits 0; real-model tests may only skip under their existing explicit environment guard.

- [ ] **Step 6: Commit documentation**

```bash
git add docs/README.md docs/features/agent-profile.md docs/features/settings.md
git commit -m "docs: explain Lulo's developer profile"
```

### Task 6: Final requirements and mutation review

**Files:**
- Review all files changed by Tasks 1-5.

- [ ] **Step 1: Re-read the approved spec line by line**

Map every requirement to a production behavior and test; add a new Red/Green cycle for any uncovered behavior.

- [ ] **Step 2: Perform the mutation check**

Confirm a test fails for each realistic break: disabled memory included, unrelated memory injected, question duplicated, built-in rules truncated, malformed reload replacing last-good state, watcher surviving dispose, profile content logged, or full conversation history copied into profile context.

- [ ] **Step 3: Run fresh verification**

Run: `dart run tool/verify.dart`

Expected: every gate exits 0 with no failures.

- [ ] **Step 4: Inspect repository state**

Run: `git status --short --branch && git log --oneline -8`

Expected: `main` is clean and shows the focused profile commits.
