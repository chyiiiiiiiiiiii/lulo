# Storage benchmark

Task 5 currently provides a reproducible, AOT-compiled smoke path for the
three SQLite access styles. It verifies one identical schema and terminal-unit
round trip, writes raw NDJSON samples, and validates SQLite integrity and
foreign keys.

From the workspace root:

```sh
dart pub get
cd apps/local_agent_macos
dart run build_runner build
flutter test test/benchmark/storage_benchmark_test.dart
mkdir -p ../../build/benchmarks/storage
dart compile exe tool/benchmark/storage_benchmark.dart \
  -o ../../build/benchmarks/storage/storage_benchmark
../../build/benchmarks/storage/storage_benchmark \
  --suite smoke \
  --source-revision "$(git rev-parse --short HEAD)" \
  --output ../../build/benchmarks/storage/smoke.ndjson
```

Resolved benchmark dependencies:

- `drift 2.34.2`
- `drift_dev 2.34.0`
- `sqlite3 3.5.0`
- `build_runner 2.15.1`

`drift_dev 2.34.5` was not usable with Flutter 3.44.1 because its Analyzer
constraint conflicts with the SDK-pinned test stack. Pub resolved the latest
compatible version, `2.34.0`, and the app pins it for reproducibility.

## Current evidence boundary

The smoke path is not decision-grade. It measures 30 `save_user_1` operations
per candidate on the main isolate with a small synthetic fixture. It does not
yet implement the full 10,000-conversation corpus, direct sqlite3 long-lived
worker, the complete background matrix, migration interruption, subprocess
crash testing, CPU/RSS sampling, or the profile-mode UI-jank target. The
executable rejects any suite other than `smoke`, so incomplete evidence cannot
silently become an adapter decision.

The production contract mismatch remains explicit:
`ConversationStorageService.saveUserTurn(Turn)` has no `ConversationId`.
Benchmark adapters take the conversation ID directly; Task 6 must not infer or
hide it.
