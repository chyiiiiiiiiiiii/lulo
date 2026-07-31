# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Local, macOS-first conversation agent. Currently at **CP0**: repository and quality baseline only — the app is an intentional empty shell (`lib/main.dart` renders one `Text`). The value in the repo right now is the quality gate and the performance-evidence harness, not features.

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

1. `dart format --set-exit-if-changed .` (root)
2. `dart analyze --fatal-infos --fatal-warnings` in `packages/agent_core`
3. `flutter analyze --fatal-infos --fatal-warnings` in `apps/local_agent_macos`
4. `dart test` in `packages/agent_core`
5. `flutter test test/features/presence/agent_presence_frame_metrics_test.dart`
6. `flutter test` in `apps/local_agent_macos`
7. `flutter test integration_test/conversation_vertical_slice_test.dart -d macos` — launches a real window; hangs if the **current Space is another app's full-screen Space** (switch to a normal desktop first)
8. `flutter build macos --profile`
9. `xcodebuild test` (RunnerTests) via `Runner.xcworkspace`, derived data in `../build/macos` — the macOS window tests
10. `swift test` in `native/inference_service`

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
