# The words are shared; the matcher is not

Turn-taking was the one part of this app that was genuinely its own — and it
was written entirely in Swift, which means it was its own only on macOS. This
records how it became portable without becoming duplicated, and the two
tidier-looking arrangements that were rejected on the way.

## What was actually in the way

`FloorControl` (who has the floor) already lived in `agent_core` as pure Dart.
`TurnCompletion` (whether the speaker has finished) did not: it sat in
`macos/Runner/VoiceHostAdapter.swift`, 80 lines of matcher plus four word
lists. Two halves of one question, split across a language boundary, and the
half with the lexicon in it was the half that could not travel.

The obvious fix — move it to Dart like its sibling — is wrong, and the reason
is in the call site rather than in the code:

```
VoiceHostAdapter.swift:887   try? await Task.sleep(for: .milliseconds(50))
VoiceHostAdapter.swift:888   self?.checkEndpoint(...)
      └─ turn.shouldFinalize(...)
              └─ TurnCompletion.requiredSilence(after: volatileText, ...)
```

Twenty times a second, inside the audio path. `pigeons/voice_host_api.dart`
had already written the conclusion down for `useUnfinishedEndings`: "applied
natively because the endpointer runs on a 50ms tick in the audio path, where
a hop across this channel per tick would cost more than the decision saves."

## Rejected: Dart computes the threshold per partial

The refinement that seems to escape it. Dart already receives every partial
transcript; let it compute `requiredSilence` when the *text* changes — a few
times a second, not twenty — and push the number down for the tick to
compare against. No hop per tick, and the rules move to Dart.

It was rejected for a race that only shows up in the failure direction that
matters. **Recognition trails the voice it heard** — `shouldFinalize`'s own
comment says "the first volatile may arrive after the room already went
quiet", which is what its 1.5s margin exists for. So a partial can land when
silence has already accumulated. Between that partial reaching Dart and the
new threshold coming back, the native tick is holding the *previous*
sentence's threshold. If the previous sentence looked settled (0.55s) and
this one is unfinished (1.4s), the turn is submitted in that window.

The window is one platform-channel round trip, so it is small. But the thing
on the other side of it is cutting a user off mid-sentence, and this
codebase has already written down that "being cut off is a worse failure
than being answered a quarter-second late." A correctness race whose payoff
is moving 80 lines is not a trade worth making.

It also does not generalise. Android's endpointer will sit in its own audio
loop for exactly the same reason macOS's does, so the Dart-owns-the-decision
arrangement buys nothing on the second platform either — it would be an
architecture adopted for portability that the port itself would not use.

## Rejected: one matcher in a shared native core

Write it once in Rust or C++ and reach it by FFI from every platform, the
way Signal and Firefox share theirs. This is the arrangement that genuinely
removes the duplication.

It is not worth it for this. The matcher is ~40 lines of suffix and word
matching over a lexicon; the price is a toolchain, cross-compilation for
three or four targets, a build step inside `verify.dart`, and a second
vendored binary to keep signed and pinned — the repo already carries one of
those and has a `PATCHES.md` to show what it costs.

## What was done

**The words are single-sourced. The matcher is written once per platform.**

`TurnCompletion` in `packages/agent_core/lib/src/voice/turn_completion.dart`
holds the only copy of the lexicon and the thresholds, plus a reference
implementation of the matcher and the corpus that pins it.
`tool/generate_turn_taking_lexicon.dart` emits them into
`macos/Runner/GeneratedTurnTakingLexicon.swift`, which is committed and read
by the Swift matcher. `verify.dart` regenerates and diffs, so a word added on
one side and not the other fails the gate.

This is not a new pattern here — it is the one `lib/l10n/generated/` and the
drift `.g.dart` output already follow: generated, committed, treated as
source. Choosing it again was mostly a matter of noticing the house already
had an answer.

| | Lives in | Reaches the platform |
|---|---|---|
| Built-in lexicon, thresholds | `agent_core` | Generated at build time, committed, gate-diffed |
| The user's own endings | `agent_core` → agent profile | `useUnfinishedEndings`, once per session (already existed) |
| The matcher | Each platform, natively | Not shared — written against the same corpus |
| The corpus | `turn_completion_test.dart` + `SpeechTurnTests.swift` | The thing that says the matchers still agree |

## Why this is safe to believe

The 26-sentence corpus table in `SpeechTurnTests.swift` was ported into
`turn_completion_test.dart` unchanged, sentence by sentence. It was read off
the Swift classifier before any of this moved, so a Dart implementation that
disagrees with it anywhere has changed behaviour rather than moved it. Both
pass it whole.

After the Swift lists were replaced by the generated ones, the 30
`SpeechTurnTests` cases pass unchanged — 121 test cases in the RunnerTests
target, 0 failures.

The gate step was checked against a planted disagreement rather than assumed
to work: changing 「然後」 to 「然後啦」 in the generated file makes
`--check` exit 1 with the file named, and regenerating restores exit 0. A
verifier that has quietly stopped detecting anything still reports success,
and this repo has been bitten by that before.

## What this does not claim

**No performance was measured, and none is claimed.** An earlier version of
this plan justified the restructure partly as a saving — the tick re-parses
`volatileText` twenty times a second even when the text has not changed. That
is true and it was never measured, and on an M-series machine parsing a
short string 20 times a second is very likely free. It was dropped rather
than kept as a supporting argument: the portability reason stands on its own,
and a plausible-sounding number nobody checked is how this repo's decision
docs have gone wrong before. If the tick is ever worth memoising, measure it
first.

**Nothing about turn-taking behaviour changed.** This is a structural change
in the sense `AGENTS.md` means it: the same decisions, reachable from
somewhere else.

## When to revisit

If a second platform is actually built and its matcher drifts from macOS's
in a way the corpus does not catch, the corpus is too small — grow the table
before reaching for a shared native core. The table is the contract; the
implementations are interchangeable as long as it holds.
