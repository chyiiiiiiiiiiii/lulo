# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Local, macOS-first conversation agent ("Lulo"). Text and voice conversation against a real on-device Gemma via LiteRT-LM both work end to end: `AppDelegate` wires `LiteRTLMRuntimeBackend` into `InferenceCoordinator`, and `lib/main.dart` selects the real runtime whenever a model is installed (falling back to `fake_runtime.dart` only with no model, or under XCTest).

The verification gates are closed: `verify_litert_app_bundle.dart` runs inside `verify.dart` against the profile build, so an app bundle that has lost the LiteRT-LM dylib, its `@rpath`, or its signature fails the gate. The one path still outside the gate is real-model coverage, which stays opt-in via `--dart-define=LOCAL_MODEL_PATH` because it puts a live, focus-stealing window on the desktop for minutes.

The context budget is real: `LiteRTLMRuntimeBackend.historyFitting` estimates tokens in UTF-8 bytes and subtracts the prompt and the reserved answer from the window, rather than spending a fixed third of it at one token per character. `estimatedTokenCount` deliberately errs high — an overflow does not degrade, it fails as an empty answer. That guard used to sit only where a conversation is *built*: every turn after the first goes to one the runtime already holds, and nothing measured what its KV cache carried — which is not the user's question but the whole turn instruction, memories and clock and open document, plus the answer. Measured against the app's own defaults: 103 tokens a turn in Chinese with nothing open, 224 with a document open, so 38 turns and 17 turns before a 4096-token window is gone. `liveConversationHasRoomForTurn` now charges a turn the same way `historyFitting` does against `Conversation.getTokenCount()`, and a conversation with no room left is rebuilt from the trimmed history — a KV cache cannot be trimmed, and the rebuild sheds the accumulated clocks and passages. See `docs/decisions/the-window-guard-only-ran-once.md`.

Runs are durable. A generation opens a row in `RunRows` before its first token, overwrites `partialText` at most once per `ConversationRepository`'s checkpoint interval, and closes behind its terminal turn; `recoverInterruptedRuns` settles whatever the last process left open, at startup before `runApp`. An answer the app died in the middle of comes back as a `TurnStatus.interrupted` turn instead of vanishing.

Turn-taking is decided by the words, not their length. `FloorControl` (`agent_core`) sorts what the user says while the agent speaks into backchannel, correction, or substance — 「對對對對對」 is agreement at any length and 「不對」 stops the answer at any length, which a four-character threshold got wrong in both directions. `TurnCompletion` (`VoiceHostAdapter`) does the same for the endpointer, moving the required silence to 1.4s after a connective and 0.55s after a visibly finished question. One part of interruption needs no words at all: every partial carries how long the burst of speech ran, and `substance` needs half a second of it as well as three syllables — a backchannel is short in every language studied, which is what stops 「うんうん」 in a language whose acknowledgements nobody has listed. Prosody was tried for the endpointer half and measured not to work here: Mandarin spends F0 on lexical tone, so final lowering does not separate a thinking pause from an ending (`sidecars/tone_probe/endpoint_pitch.py`). Both lexicons are read back over every sentence in the zh-TW corpus, and both extend from `turnTaking` in the watched agent profile — the built-in lists are a guess about how someone talks, and the person talking can disprove it without a rebuild. See `docs/decisions/turn-taking-by-words.md`. The recogniser's own confidence now reaches the screen too: a turn whose weakest span scored under 0.85 is captioned rather than shown as if it were certain. Settings › Taking turns draws every ruling under the conversation, because a rule nobody can see fire is indistinguishable from a bug.

The turn latency is measured, not guessed. `AgentPromptContext` splits into a `systemInstruction` prefilled once per conversation and a `turnInstruction` read again with every question: sending the stable half inside every user message re-prefilled it every turn, measured in the app at 1648ms to the first token against 362ms for a settled Chinese turn, and at nothing at all in English — Han costs several tokens a character where English costs a fraction of one, so prompt cost measured in English says nothing about prompt cost in Chinese. `VoiceTurnLatency` and two adapter log lines now account for one turn end to end. Before changing the endpointer's 0.8s or the prompt's shape, read `docs/decisions/voice-turn-latency.md` — the corpus has mid-sentence pauses of 1.02s, and Smart Turn v3.2 was measured and does not separate them.

An answer is something the user can act on, not only read. Every turn carries
copy, the newest answer carries `重新回答`, and the newest question carries an
in-place rewrite — a model this size is wrong in ways a second attempt fixes,
and without these the only way past a bad answer was to type the question
again. Three things remember the answer being replaced and all three have to
let go: the projection, the store (`dropFromLastQuestion`, named by what it
means because the view hides an empty cancelled turn the store keeps, so a
position counted from the screen is not a position in the store), and the
runtime, whose KV cache still holds it — `ConversationRepository` releases the
session for the same reason `deleteConversation` does. Only the newest
exchange is retryable. See `docs/features/conversation.md`.

The profile is editable from the app. `AgentProfileSettings` writes the same
`agent_profile.json` in the same schema through `AgentProfileStore.save`, so
there is no second copy — and the prompt, the recogniser and the endpointer
all read `profileStore.current`, so an edit is in force on the next turn.
Two things are load-bearing: `AgentProfile.copyWith` rebuilds `floorControl`
rather than carrying it over, because it is derived from `turnTaking` and
carrying it would save the word and go on ignoring it; and
`encodeAgentProfile` writes every field, because the decoder reads a missing
list as empty. With no model installed the app opens on `FirstRun` rather than
on a conversation the built-in preview would answer with the same sentence
every time.

The orb ends inside its own square. `agentPresenceSilhouetteFraction` is 0.75
and the native click catcher fills 0.62, both measured from a real-shader
capture that `verify.dart` re-runs: the halo used to paint 23/255 at 0.70 and
was still visible at 0.95, which on the desktop read as a faint circle wrapped
around the orb, and the catcher used to take every click within half a side of
the centre. See `docs/features/presence.md`.

Which language works depends on the way in, not on the language.
`docs/features/voice.md` › *What each path hears* is the one place the three
are measured beside each other: typing has no disadvantage, holding the key
works in both and is worse in English (3.8% heard CER against 1.6%), and the
full-duplex path pins one locale for the whole session and has never been
measured in English at all. The English problem is an interface question
before it is a model one.

The interface speaks whatever the Mac speaks. Every user-facing string lives
in `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb` (Traditional) and is reached
through `AppLocalizations.of(context)`; `MaterialApp` takes the system locale
and falls back to English. Before this the conversation was in Chinese and the
settings sheet was in English, which is not a language but two halves of an app
written by whoever happened to be typing. A widget test that renders a string
must install `AppLocalizations.localizationsDelegates`, and one that asserts a
particular string must pin `locale:` — the harness's default is English and a
test that takes it is asserting the harness's language. `app_zh_Hant.arb` is
empty on purpose and inherits everything from `app_zh.arb`: it exists so that
zh-Hant is in `supportedLocales`, because the resolved locale is what picks the
CJK font and a bare `zh` renders Simplified punctuation — a centred 「，」 with a
gap after it. `flutter pub get` reporting `zh_Hant: N untranslated` is that file
working as intended — N is however many keys `app_zh.arb` has, and it moves
with every string added.

There is no tool calling, and that is now a measured decision rather than a
gap. Probed against the real model with a clock tool registered, gemma-4-E4B
called it 5 times out of 5 with no system message and **0 times out of 5**
under this app's own system instruction — either language, either
temperature, and still 0 when a further paragraph ordered it to use the
tool. It invents a confident wrong time instead, in an app whose core
instruction says 不捏造資訊. Telling it the time in the prompt answers 5/5 in
both languages, so `composeAgentPrompt` takes
a `now` and puts the clock in the **turn** half, where it costs nothing the
turn was not already paying. English used to read 3/5 there and does not:
the scorer's minute list held 「五十三」 and no English word form, so a clock
spelled out scored right in one language and wrong in the other — a scorer
uneven between two languages manufactures a difference that then reads as a
finding about the model, and two paragraphs had been written about it. The
probe now prints every reply that scored wrong rather than the last one,
because an invented time and a real one the scorer could not parse are the
same number and different problems. Read
`docs/decisions/tool-calling-readiness.md`
before building on tool calling: the probe is checked in and skipped by
default, and the thing that would actually fix it — constrained decoding —
is missing from the vendored runtime.

Two settings that named something they did not reach now reach it.
`AgentProfile.vocabulary` documented itself as biasing the recogniser while
only ever reaching the text refiner — the recogniser ran off a hardcoded
list, and the only words it learned came from the agent's own answers; it
crosses the boundary now through `VoiceHostApi.useSpokenVocabulary`, and
Settings can edit it, which it could not before. Read that as a setting
reaching its target and not as an accuracy win: `SpokenVocabularyBook`
records a bias of thirty-two terms changing the transcript by not one
character. Separately, the app called itself resident and was not there
after a restart, because nothing asked macOS to start it; `LaunchAtLogin`
does now. It is deliberately absent from `AppSettings` — the registration
belongs to macOS, survives reinstalls, and can be revoked in System Settings
while the app is not running, so it is read back rather than remembered, in
four states rather than two.

A word it keeps mishearing can be taught once. `AgentProfile.misheard` holds
`MisheardWord(heard, meant)` pairs and `DeterministicTranscriptRefiner`
applies them, so 「Dark text」 becomes 「Dart test」 in the question that
actually gets asked. Deliberately a substitution rather than another entry in
`vocabulary`: that list is a hint to the recogniser and the hint was measured
doing nothing, while a substitution cannot fail the same way. Three things
are load-bearing and each is pinned by a test — corrections run **after** the
vocabulary casing pass, because whatever runs last wins and a term typed into
the vocabulary list in the wrong case otherwise undid the correction; word
breaks are checked **per end**, because a rule requiring Latin at both ends
skipped the check entirely for 「台中 weather」 and every other mixed-script
rule this app is actually for; and matching walks graphemes, because indexing
code units moved a combining accent onto the replacement.

Speaking into the clipboard was built and taken back out, and
`docs/decisions/dictation-cannot-share-the-tap.md` is the reason. A hold-to-
dictate key cannot carve a mode out of the conversation's microphone tap:
that tap serves a live endpointer, a voice-activity detector and a
half-duplex mute, and every guard added for dictation broke one of them —
skipping the VAD froze `lastVoice` and made the endpointer fire *sooner*,
submitting a truncated question mid-dictation, and letting dictation past
the mute recorded the agent's own voice in the one mode with no echo
canceller. The next attempt needs its own `AVAudioEngine`, and that is now
measured rather than hoped: `SecondAudioEngineTests` passes in 2.4s with
both taps receiving buffers, so the plan in that document is unblocked. It
was twice written up as impossible — first as a TCC prompt nobody could
click, then as a wedged virtual HAL driver the machine owner would have to
uninstall — and both were an elimination argument handing the remainder to
the most elaborate suspect left standing. CoreAudio was wedged; the machine
was restarted; it works. Three fixes from
that work were kept because they stand alone: `GlobalHotKeyController.nextID`
is now `static` (it was per-instance, and Carbon routes on `(signature, id)`
with one shared signature, so any second hotkey silently answered for the
first), `sweepHeldClips` deletes held-speech recordings after an hour, and
`transcribeHeld` returns `String?` so "no recogniser" stays distinct from
"heard nothing".

The two sidecars fail silently by design and no longer fail invisibly. Both
live outside this repository, are started by hand, and take the voice and the
batch recogniser down with them — until now the only symptom was an agent
that heard, thought, wrote, and stayed quiet. `SidecarHealthProbe` opens a
socket against 46557 and 46558 when Settings opens and says which is down.
It reports rather than offers to fix: the sandbox forbids spawning a
subprocess, so a restart button would be a button that does nothing. It is
injected from the composition root and absent by default, because the real
probe opens a socket with a real timeout and a widget test that merely builds
the app must not hold a pending timer for a question it never asked.

A recording the user already has can be written out. The batch recogniser is
installed, tuned for this user's language, and measured at 1.6% character
error on zh — and the only way to reach it was to hold a key at a live
microphone, so a 課堂錄音 in Downloads could not use the best recogniser on
the machine. Settings picks a file through the system panel, hands the path
to the same sidecar the hold key uses with a budget for a whole recording
rather than one sentence, and saves the text through the save panel because
a sandboxed app may write where the panel says and nowhere else. Nothing
came back is reported rather than swallowed, and the section beside it names
the sidecar that is most likely why.

Text selected in another app reaches Lulo in one step. `NSServices` in
`Info.plist` puts "Ask Lulo about this" in every app that handles text —
which needs no Accessibility permission and works on the deployment target,
unlike reading the screen. `SelectionService.text(from:)` is the testable
half; a whitespace-only selection is refused, because the system offers the
item whenever any string is on the pasteboard. It **seeds the composer and
does not send**: a selection is not a question, the user still has to say
what they want done with it, and what they were already typing is kept.
Writing the answer back over the selection is **not available**, and that is
checked rather than assumed: a Services handler is synchronous — `(pasteboard,
userData, error)` returning `void`, no completion handler, no async variant —
so anything returned must be on the pasteboard before it returns, which means
blocking the calling app's main thread across a Pigeon hop and a whole
generation. The alternative is Accessibility permission and synthetic
keystrokes, which is what the comparable products do and is not a permission
this app should ask for to save two steps. See `docs/features/settings.md`.

Questions can be answered out of one file the user picked. Not retrieval-
augmented generation, which needs an embedding model, chunking and a vector
store all inside this process because the sandbox cannot spawn one — and then
the retrieved chunks share a 4096-token window with the question and the
reserved answer, leaving room for two or three, so retrieval quality decides
everything with no room to recover. `passagesFor` instead takes whole
paragraphs the question's own words locate, bounded, into the **turn** half.
Whole paragraphs because a sentence cut out of the clause it depends on is
how a model confidently answers the opposite; Han matched by substring for
the reason `searchConversations` documents; single characters dropped in both
scripts, because matching 「的」 or "the" makes every passage relevant, which
is the same as none and costs the whole budget to find out. A question the
document says nothing about carries none of it, rather than the first
paragraph. `documentOf` is read at compose time, so a file left open that the
next question has nothing to do with costs nothing — which is what makes
leaving one open safe.

Toolchain is pinned by CI: Flutter **3.44.1** stable, Dart SDK `^3.12.0`.

## Layout

Native Dart **pub workspace** (`workspace:` in the root `pubspec.yaml`), not melos. One shared `pubspec.lock` at the root; members declare `resolution: workspace` and are resolved together.

| Path | What |
|---|---|
| `packages/agent_core` | Pure Dart. Contracts and logic. **Must never import Flutter.** Uses `package:test`. |
| `apps/local_agent_macos` | Flutter macOS app. Uses `flutter_test` / `integration_test`. |
| `apps/local_agent_macos/lib/l10n` | The UI's own words. `*.arb` are edited; `generated/` is written by `flutter pub get` and committed, like the drift output beside it. |
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
14a. `flutter test integration_test/agent_presence_silhouette_test.dart -d macos` — runs the real shader and reads the orb's alpha back per ring, so nothing of the presence survives past `agentPresenceSilhouetteFraction` onto the user's desktop. Also launches a real window
15. `flutter build macos --profile`
16. `dart tool/verify_litert_app_bundle.dart <bundle>` — static checks that the profile build still carries the LiteRT-LM dylib, its `@rpath`, and a valid signature. The bundle path is resolved from `PRODUCT_NAME` rather than hard-coded, and a path that cannot be resolved is reported as a failing step rather than a skipped one
16a. `dart apps/local_agent_macos/tool/verify_release_entitlements.dart` — the shipped build's entitlements. The gate builds `--profile`, which signs with `DebugProfile.entitlements`, so nothing else here ever looks at the file a released app is actually signed with; a capability granted there and not in Release fails only in the build nobody tests. It also rejects `--` inside an XML comment, which `plutil` and `codesign` accept and every strict parser refuses
17. `xcodebuild test` (RunnerTests) via `Runner.xcworkspace`, derived data in `../build/macos_window_tests` — the macOS window tests. Deliberately not Flutter's own build directory: two build systems over one Products directory delete each other's outputs
18. `swift test` in `native/inference_service`

Before running the gate, quit any running Lulo.app first — a live instance with the same bundle ID makes the xcodebuild test host hang ("test runner hung before establishing connection").

Sweep again **after** it finishes. Steps 14, 14a and 17 launch real windows, and an instance that outlives its test stays in the Dock and hangs the next run for the same reason:

```sh
./tool/sweep_app_instances.sh
```

It matches the **build directory**, not the process name, so a Lulo installed to `/Applications` — the user's own resident agent — is left alone, and so are the sidecars, which live outside this repository and take voice and the batch recogniser down with them. It prints only when it closed something.

`.claude/settings.json` runs it as a `Stop` hook, so it also happens at the end of every turn without anybody remembering to. Report the gate's result and the sweep together anyway: the hook fires after the reply is written, so a report that does not mention the sweep was written before it ran.

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
