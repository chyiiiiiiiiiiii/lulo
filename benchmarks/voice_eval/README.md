# Lulo voice evaluation

This package compares voice-pipeline candidates against one private,
versioned Taiwan Mandarin corpus. It does not load a model and does not send
audio or text off the machine.

## What it measures

- literal character error rate, including punctuation and Latin case;
- spoken character error rate, ignoring punctuation, whitespace and Latin
  case;
- raw and refined transcripts independently;
- early, expected-window, late and missing shadow endpoint decisions;
- TTS first-audio latency, completion latency and real-time factor;
- manual blind ratings for Taiwan Mandarin naturalness, voice consistency,
  pacing, intelligibility and preference.

Timing does not measure naturalness. CER does not prove that a transcript
preserved intent. Use the machine report and blind listening review together.

## Private golden WAV files

The scripts live in `corpus/zh-TW-v1.json`. Record mono WAV files using the
exact relative paths in that manifest and place them below `corpus/audio/`.
That directory ignores all audio files. Never force-add personal recordings
to Git.

A metadata-only inventory works before recordings exist:

```sh
dart run tool/evaluate.dart \
  --corpus corpus/zh-TW-v1.json \
  --output /tmp/lulo-voice-inventory
```

Use `--require-audio` for a real corpus run. It fails before creating output
when any source WAV is missing.

## Candidate files

A candidate is a JSON envelope with `kind` set to `transcript`, `turn`, or
`tts`. See the full contract in
`../../docs/superpowers/specs/2026-08-02-taiwan-mandarin-voice-eval-design.md`.
Pass candidate files repeatedly:

```sh
dart run tool/evaluate.dart \
  --corpus corpus/zh-TW-v1.json \
  --candidate /tmp/apple-transcript.json \
  --candidate /tmp/smart-turn-shadow.json \
  --output /tmp/lulo-voice-run \
  --require-audio
```

The output contains `report.json` and a transcript-free `summary.md`. TTS runs
also produce `review.json` with opaque labels and a separate
`review-key.json`. Complete the blind review before opening the key.

Smart Turn evidence is shadow-only: candidate timestamps are scored here but
never invoke Lulo's production endpoint.

Qwen transcript proposals follow the same rule. The Flutter app's optional
loopback provider is disabled by default and cannot change live text. During
an explicit corpus run, attach corpus case IDs, take a bounded evidence
snapshot, and pass it to `buildTranscriptShadowCandidateExport`. The builder
returns JSON-compatible data only; the development runner chooses the output
path. Ordinary app startup never writes private transcripts.

## Development

```sh
dart pub get
dart test
dart analyze --fatal-infos --fatal-warnings
```
