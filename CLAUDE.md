# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Local, macOS-first conversation agent ("Lulo"). Text and voice conversation against a real on-device Gemma via LiteRT-LM both work end to end: `AppDelegate` wires `LiteRTLMRuntimeBackend` into `InferenceCoordinator`, and `lib/main.dart` selects the real runtime whenever a model is installed (falling back to `fake_runtime.dart` only with no model, or under XCTest).

The verification gates are closed: `verify_litert_app_bundle.dart` runs inside `verify.dart` against the profile build, so an app bundle that has lost the LiteRT-LM dylib, its `@rpath`, or its signature fails the gate. The one path still outside the gate is real-model coverage, which stays opt-in via `--dart-define=LOCAL_MODEL_PATH` because it puts a live, focus-stealing window on the desktop for minutes.

The context budget is real: `LiteRTLMRuntimeBackend.historyFitting` estimates tokens in UTF-8 bytes and subtracts the prompt and the reserved answer from the window, rather than spending a fixed third of it at one token per character. `estimatedTokenCount` deliberately errs high — an overflow does not degrade, it fails as an empty answer.

Runs are durable. A generation opens a row in `RunRows` before its first token, overwrites `partialText` at most once per `ConversationRepository`'s checkpoint interval, and closes behind its terminal turn; `recoverInterruptedRuns` settles whatever the last process left open, at startup before `runApp`. An answer the app died in the middle of comes back as a `TurnStatus.interrupted` turn instead of vanishing.

Turn-taking is decided by the words, not their length. `FloorControl` (`agent_core`) sorts what the user says while the agent speaks into backchannel, correction, or substance — 「對對對對對」 is agreement at any length and 「不對」 stops the answer at any length, which a four-character threshold got wrong in both directions. `TurnCompletion` (`VoiceHostAdapter`) does the same for the endpointer, moving the required silence to 1.4s after a connective and 0.55s after a visibly finished question. Both are read back over every sentence in the zh-TW corpus, and both extend from `turnTaking` in the watched agent profile — the built-in lists are a guess about how someone talks, and the person talking can disprove it without a rebuild. See `docs/decisions/turn-taking-by-words.md`. The recogniser's own confidence now reaches the screen too: a turn whose weakest span scored under 0.85 is captioned rather than shown as if it were certain. Settings › Taking turns draws every ruling under the conversation, because a rule nobody can see fire is indistinguishable from a bug.

The turn latency is measured, not guessed. `AgentPromptContext` splits into a `systemInstruction` prefilled once per conversation and a `turnInstruction` read again with every question: sending the stable half inside every user message re-prefilled it every turn, measured in the app at 1648ms to the first token against 362ms for a settled Chinese turn, and at nothing at all in English — Han costs several tokens a character where English costs a fraction of one, so prompt cost measured in English says nothing about prompt cost in Chinese. `VoiceTurnLatency` and two adapter log lines now account for one turn end to end. Before changing the endpointer's 0.8s or the prompt's shape, read `docs/decisions/voice-turn-latency.md` — the corpus has mid-sentence pauses of 1.02s, and Smart Turn v3.2 was measured and does not separate them.

Next up: tool calling with a permission layer. There is no tool calling today.

Toolchain is pinned by CI: Flutter **3.44.1** stable, Dart SDK `^3.12.0`.

## Layout

Native Dart **pub workspace** (`workspace:` in the root `pubspec.yaml`), not melos. One shared `pubspec.lock` at the root; members declare `resolution: workspace` and are resolved together.

| Path | What |
|---|---|
| `packages/agent_core` | Pure Dart. Contracts and logic. **Must never import Flutter.** Uses `package:test`. |
| `apps/local_agent_macos` | Flutter macOS app. Uses `flutter_test` / `integration_test`. |
| `tool/verify.dart` | The quality gate. |
| `.github/workflows/ci.yml` | Runs `dart tool/verify.dart` on macOS. |

Run `flutter pub get` **from the repository root** — it resolves the whole workspace. Running it inside a member is not how this repo is set up.

## Commands

Full gate (do this before any checkpoint commit):

```sh
dart run tool/verify.dart
```

`verify.dart` runs its subprocesses **sequentially** and buffers each one's output, printing it grouped per-command at the end rather than streamed. It always runs everything and reports every failure — a failing early step does not short-circuit the rest. The steps are:

Before the first step it deletes the previously built app bundle, because `flutter build macos` rewrites App.framework without always re-signing the outer bundle, and the stale signature then fails the bundle gate as `nested code is modified`.

1. `dart format --set-exit-if-changed .` (root)
2. `dart analyze --fatal-infos --fatal-warnings` (root — this is where `tool/` lives)
3. `dart analyze --fatal-infos --fatal-warnings` in `packages/agent_core`
4. `flutter analyze --fatal-infos --fatal-warnings` in `apps/local_agent_macos`
5. `dart test` in `packages/agent_core`
6. `dart tool/macos_app_bundle_test.dart` — the bundle path resolver
7. `dart tool/verify_litert_app_bundle_test.dart` — the bundle gate's own tests
8. `dart analyze --fatal-infos --fatal-warnings` in `benchmarks/voice_eval`
9. `dart test` in `benchmarks/voice_eval`
10. `python3 -m unittest discover` in `sidecars/qwen_transcript_refiner`
11. `python3 -m unittest discover` in `sidecars/smart_turn_shadow`
11a. `python3 -m unittest discover` in `sidecars/tone_probe` — needs `numpy`; CI installs it from that directory's `requirements.txt`
11b. `python3 -m unittest discover` in `sidecars/pronunciation`
12. `flutter test test/features/presence/agent_presence_frame_metrics_test.dart`
13. `flutter test` in `apps/local_agent_macos`
14. `flutter test integration_test/conversation_vertical_slice_test.dart -d macos` — launches a real window; hangs if the **current Space is another app's full-screen Space** (switch to a normal desktop first)
15. `flutter build macos --profile`
16. `dart tool/verify_litert_app_bundle.dart <bundle>` — static checks that the profile build still carries the LiteRT-LM dylib, its `@rpath`, and a valid signature. The bundle path is resolved from `PRODUCT_NAME` rather than hard-coded, and a path that cannot be resolved is reported as a failing step rather than a skipped one
17. `xcodebuild test` (RunnerTests) via `Runner.xcworkspace`, derived data in `../build/macos_window_tests` — the macOS window tests. Deliberately not Flutter's own build directory: two build systems over one Products directory delete each other's outputs
18. `swift test` in `native/inference_service`

Before running the gate, quit any running Lulo.app first — a live instance with the same bundle ID makes the xcodebuild test host hang ("test runner hung before establishing connection").

Individual commands during iteration:

```sh
dart test test/conversation_id_test.dart                 # in packages/agent_core
dart test -n 'ConversationId compares equal'             # single test by name
flutter test test/app/bootstrap_test.dart                # in apps/local_agent_macos
flutter test --plain-name 'local bootstrap'              # single test by name
```

`flutter test` does **not** pick up `integration_test/`. The frame-timing test is a driver run in profile mode against a real macOS window, and is what produced the checked-in evidence at `build/cp0_frame_timing/empty_shell_frame_timing.json`:

```sh
# in apps/local_agent_macos
flutter drive \
  --driver=test_driver/empty_shell_frame_timing_test.dart \
  --target=integration_test/empty_shell_frame_timing_test.dart \
  -d macos --profile
```

## Lint strictness

`analysis_options.yaml` is stricter than `flutter_lints` alone, and `--fatal-infos` means every lint is a gate failure. The ones that bite when writing new code:

- **`public_member_api_docs: true`** — every public class, constructor, field, getter, and top-level function needs a `///` comment. This is why existing code is doc-commented on every member; match it.
- `strict-casts`, `strict-inference`, `strict-raw-types`, plus `inference_failure_on_function_invocation` and `inference_failure_on_untyped_parameter` as **errors** — generic type arguments must be written explicitly. Existing code writes `<String>[...]`, `Map<String, Object?>`, and explicit local types rather than `var`; keep doing that.
- `avoid_print`, `avoid_dynamic_calls`, `always_declare_return_types`, `directives_ordering`.

## Architecture rules (from AGENTS.md)

- `packages/agent_core` stays Flutter-free.
- Strict **Red/Green TDD** for every behavioral change — write the failing test first.
- `apps/local_agent_macos/lib/app/bootstrap.dart` (and a future `app_composition.dart`) is the composition root. Dependencies are constructed there and passed down.
- **No globals, no static singletons, no service locator.** Inject explicitly.

## Performance gate

`lib/performance/empty_shell_frame_budget.dart` parses a Flutter `FrameTimingSummarizer` report and enforces the CP0 guardrail: p99 build **and** p99 raster must each be ≤ **12 ms**, and both stages must have at least one sample (an empty report fails rather than trivially passing). `evaluateFrameTimingReport` is pure and unit-tested in `test/performance/`; the integration test feeds it real engine timings and writes the result into `binding.reportData`. Bootstrap targets 120 fps (`BootstrapConfig.targetFrameRate`).
