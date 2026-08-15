# The full-duplex recogniser, over files

`docs/features/voice.md` scored three ways in beside each other and the
full-duplex column read **never measured** for English. That was not an
oversight about English. The full-duplex recogniser had no way to be measured
at all: `voice_eval` scores files, and `SpeechTranscriber` lived in exactly one
place — `VoiceHostAdapter`, wired to a live `AVAudioEngine` — so the only way
to get a transcript out of it was to speak into the machine. A number obtained
that way cannot be re-run, and a column that cannot be re-run stays empty.

`SpeechAnalyzer` never needed the engine. It takes any
`AsyncSequence<AnalyzerInput>`, so a corpus `.wav` read off disk feeds it the
same way a microphone tap does.
`macos/RunnerTests/FullDuplexCorpusProbeTests.swift` does that and writes the
candidate JSON in this directory.

## The numbers

| | Corpus | Cases | spoken CER | heard CER |
|---|---|---:|---:|---:|
| Chinese | `zh-TW-v1` | 12 | **14.64%** | **6.04%** |
| English | `en-spoken-v1` | 16 | **16.36%** | **13.39%** |

Read the **heard** column. `spokenCer` folds punctuation and Latin case but
**not numerals**, and the Chinese corpus spells out 一萬二 and 三點半 where the
recogniser writes `12,000` and `3:30` — so Chinese pays a penalty there for a
transcription convention rather than for mishearing. `heardCer` removes numbers
from both sides and asks only whether the words were heard.

On that measure **English is 2.2× worse than Chinese on the full-duplex path**,
and the two spoken-CER figures looking comparable is an artifact of the
numeral fold. This is the opposite of the impression the headline numbers give.

The comparison is between two corpora, not two readings of one: different
sentences, different lengths, different speaker. It is enough to say English
is clearly worse and not enough to put a ratio in a slide.

## Why the harness can be believed

The Chinese run scores **14.64%** spoken CER. `voice_eval/README.md` already
recorded **14.6%** for `SpeechAnalyzer` on the same corpus, measured the old
way. A file-fed harness reproducing the live-microphone number to three
significant figures is the evidence that it is the same pipeline.

What it does not reproduce is the engine — no voice-processing unit, no
half-duplex mute, no microphone array. So this measures the **recogniser**. A
live session can be worse than this; it cannot be better.

## The vocabulary bias does nothing, again

`candidate-full-duplex-en-nobias.json` is the same 16 English cases with
`contextualStrings` withheld. It is **identical to the biased run in all 16
cases, character for character.**

This is not a broken harness. `CLAUDE.md` already records the same result from
the other direction: "`SpokenVocabularyBook` records a bias of thirty-two terms
changing the transcript by not one character." Two independent measurements now
say the same thing, which is also why the biased candidate here can be trusted
to represent the shipping pipeline — there is nothing for the bias to change.

The errors it would have to fix are the ones it cannot: `LiteRT` → "light RT",
`Gemma` → "Jemmon", `Dart test` → "Dot test" / "dog test", `Flutter 3.44.1` →
"Brother 3.44.1", "commits" → "comemates". Every one of them is a correctly
spelled ordinary English word, which is exactly the failure
`AgentProfile.misheard` exists for and a hint list cannot reach.

## Re-running it

```sh
cd apps/local_agent_macos/macos
xcodebuild build-for-testing -workspace Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination platform=macOS \
  -derivedDataPath ../build/macos_window_tests

TEST_RUNNER_VOICE_CORPUS=$PWD/../../../benchmarks/voice_eval/corpus/en-spoken-v1.json \
TEST_RUNNER_VOICE_CANDIDATE_OUT=candidate-full-duplex-en.json \
  xcodebuild test-without-building -workspace Runner.xcworkspace -scheme Runner \
    -configuration Debug -destination platform=macOS \
    -derivedDataPath ../build/macos_window_tests \
    -only-testing:RunnerTests/FullDuplexCorpusProbeTests
```

Two things bite. The `TEST_RUNNER_` prefix is required — `xcodebuild` does not
hand the shell's environment to the test process, and without it the run
reports **success** having skipped the only test in it. And the test host is
the real sandboxed app, so it may read the corpus out of the repository and may
not write the candidate back beside it; the file lands in the host's temporary
directory and the run prints the path. Copy it out from there.

Then score it:

```sh
cd benchmarks/voice_eval
dart run tool/evaluate.dart \
  --corpus corpus/en-spoken-v1.json \
  --candidate <the file the probe printed> \
  --output /tmp/report-fd-en
```
