# Lulo voice evaluation

This package compares voice-pipeline candidates against one private,
versioned Taiwan Mandarin corpus. It does not load a model and does not send
audio or text off the machine.

## What it measures

- literal character error rate, including punctuation and Latin case;
- spoken character error rate, ignoring punctuation, whitespace and Latin
  case;
- heard character error rate, ignoring how numbers are written as well;
- raw and refined transcripts independently;
- early, expected-window, late and missing shadow endpoint decisions;
- TTS first-audio latency, completion latency and real-time factor;
- manual blind ratings for Taiwan Mandarin naturalness, voice consistency,
  pacing, intelligibility and preference.

Timing does not measure naturalness. CER does not prove that a transcript
preserved intent. Use the machine report and blind listening review together.

### `spokenCer` and `heardCer`

Spoken CER folds punctuation, whitespace and Latin case. It does **not** fold
numerals, and that is a real cost rather than an oversight: recognisers write
`12,000` and `3:30` where `corpus/zh-TW-v1.json` spells out 一萬二 and 三點半,
and the scorer charges every character of the difference. Measured on Apple's
`SpeechAnalyzer`, those two cases alone score 61.5% and 41.7% against a 14.6%
mean over twelve, while six of the twelve are character-perfect. Both were
heard correctly.

`heardCer` is the same score with every number removed from both sides. It
answers "did it hear the words", where `spokenCer` answers "did it write the
sentence". Neither replaces the other, and `heardCer` is blind by
construction: a recogniser that gets every number wrong scores perfectly on
it. Read the pair.

The fold is removal rather than conversion. Converting 一萬二 to `12000` needs
a Chinese number parser and a way to know that 三點五 is 3.5 while 三點半 is
half past three; that is a real piece of work whose bugs would be invisible
inside an aggregate, and it has not been done.

Bias also matters when comparing candidates. The app hands the transcriber
`contextualStrings` from the conversation's vocabulary, which is what keeps
Flutter from coming back as Flater. A candidate produced without that bias is
not measuring the same pipeline.

## Producing an ASR candidate

`tool/asr_probe.py` runs any MLX Whisper checkpoint over the corpus and
writes `kind: transcript` candidate JSON, through the same post-processing
and the same protected vocabulary the app applies — so what is compared is
the path the app would take, not two raw model outputs. It needs the
`mlx_whisper` environment that serves `~/dev/lulo-tts/ears.py`.

```sh
~/dev/lulo-tts/.venv-ears/bin/python tool/asr_probe.py \
  MediaTek-Research/Breeze-ASR-25 breeze-asr-25 /tmp/breeze.json
dart run tool/evaluate.dart --corpus corpus/zh-TW-v1.json \
  --candidate /tmp/breeze.json --output /tmp/report
```

Two runs of it are checked in under `evidence/batch-asr-candidates/`; see
[../../docs/decisions/batch-asr-candidates.md](../../docs/decisions/batch-asr-candidates.md).

The corpus and the decode language are optional trailing arguments, because
`ears.py` pins `language="zh"` and "can this model hear English" is a
different question from "can the shipped configuration hear English":

```sh
python3 tool/say_english_corpus.py          # regenerates the WAVs
~/dev/lulo-tts/.venv-ears/bin/python tool/asr_probe.py \
  Kenji8000/Breeze-ASR-25-mlx breeze-zh /tmp/breeze-en.json \
  corpus/en-synthetic-v1.json zh
```

`corpus/en-synthetic-v1.json` is macOS `say` output rather than a person, so
unlike the zh-TW corpus its audio is a function of the manifest and is
regenerated instead of recorded. It is still not committed — `corpus/audio`
ignores everything, and that rule stays simple.

## The English cases a synthesizer cannot answer

`corpus/en-spoken-v1.json` is the same eight sentences plus eight more, to be
read by a person into `corpus/audio/en-spoken/`. The first eight are repeated
deliberately: paired against the synthetic run, the only variable left is the
speaker, so the difference *is* the answer to "how much did synthesis flatter
the result".

The other eight are the things `say` cannot produce — a self-correction, a
filler, a one-word utterance, a mid-sentence pause, numbers, product names
that are also ordinary English words, and one English sentence carrying a
Chinese word, which is the reverse of every code-switching case measured so
far.

Record mono WAV at the exact paths in the manifest, then:

```sh
~/dev/lulo-tts/.venv-ears/bin/python tool/asr_probe.py \
  Kenji8000/Breeze-ASR-25-mlx breeze-spoken /tmp/spoken.json \
  corpus/en-spoken-v1.json zh
dart run tool/evaluate.dart --corpus corpus/en-spoken-v1.json \
  --candidate /tmp/spoken.json --output /tmp/report --require-audio
```

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
