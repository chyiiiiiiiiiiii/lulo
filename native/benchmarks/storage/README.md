# Storage benchmark

Task 5 currently provides a reproducible, AOT-compiled smoke path for the
three SQLite access styles. It verifies one identical schema and terminal-unit
round trip, writes raw NDJSON samples, and validates SQLite integrity and
foreign keys.

From the workspace root:

```sh
dart pub get
cd benchmarks/storage_benchmark
dart run build_runner build
dart test test/benchmark/storage_benchmark_test.dart
mkdir -p ../../build/benchmarks/storage
dart compile exe tool/benchmark/storage_benchmark.dart \
  -o ../../build/benchmarks/storage/storage_benchmark
SOURCE_REVISION="$(git rev-parse HEAD)"
CONTENT_FINGERPRINT="$(shasum -a 256 \
  tool/benchmark/storage_benchmark.dart \
  tool/benchmark/storage_benchmark.g.dart \
  pubspec.yaml ../../pubspec.lock | shasum -a 256 | awk '{print $1}')"
../../build/benchmarks/storage/storage_benchmark \
  --suite smoke \
  --source-revision "$SOURCE_REVISION" \
  --content-fingerprint "sha256:$CONTENT_FINGERPRINT" \
  --build-mode aot \
  --output ../../build/benchmarks/storage/smoke.ndjson
```

Resolved benchmark dependencies:

- `drift 2.34.2`
- `drift_dev 2.34.0`
- `sqlite3 3.5.0`
- `build_runner 2.15.1`

`drift_dev 2.34.5` was not usable with Flutter 3.44.1 because its Analyzer
constraint conflicts with the SDK-pinned test stack. Pub resolved the latest
compatible version, `2.34.0`, and the isolated benchmark package pins it for
reproducibility.

## Current evidence boundary

All four packages are isolated in the `benchmarks/storage_benchmark` workspace
member. The production Flutter app has no direct or transitive dependency on
the benchmark package, Drift, or sqlite3, so a No-selection checkpoint does
not ship a candidate database runtime in the application.

The smoke path is not decision-grade. It measures 30
`save_terminal_1` transactions per candidate on the main isolate with a small
synthetic fixture. Each iteration first inserts an untimed user turn, then the
timed terminal unit inserts the assistant turn, generation row, and
conversation metadata update. The runner restores all rows and validates exact
count and final content plus SQLite integrity, foreign keys, generation
ownership, and conversation metadata. It does not
yet implement the full 10,000-conversation corpus, direct sqlite3 long-lived
worker, the complete background matrix, migration interruption, subprocess
crash testing, CPU/RSS sampling, or the profile-mode UI-jank target. The
executable rejects any suite other than `smoke`, so incomplete evidence cannot
silently become an adapter decision.

The production contract mismatch remains explicit:
`ConversationStorageService.saveUserTurn(Turn)` has no `ConversationId`.
Benchmark adapters take the conversation ID directly; Task 6 must not infer or
hide it.
