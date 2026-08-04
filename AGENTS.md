# Flutter Local Agent

- Keep `packages/agent_core` pure Dart; it must never import Flutter.
- Follow strict Red/Green TDD for every behavioral change.
- Keep `bootstrap.dart` and future `app_composition.dart` as the composition root.
- Do not add globals, static singletons, or a service locator.
- Run `dart run tool/verify.dart` before a checkpoint commit.

## What this agent is for

**Taiwanese Mandarin.** Anything measured only in English has not been
measured. Han costs several tokens a character where English costs a
fraction of one, so the two are not the same workload and a result from one
does not carry to the other: re-sending the profile inside every question
cost 1.4s a turn in Chinese and nothing at all in English, and an
English-only real-model slice sat green over it. When a change could touch
cost, quality, or the recogniser, the Chinese case is the one that decides.

## Building

- **Grow the system in layers.** Start from the smallest version that works
  end to end and add each capability on top of a product that already works.
  Never trade a working product for unfinished complexity.
- **Choose the simplest implementation that fully meets the current
  requirement.** No speculative abstractions, configuration, or indirection.
- **Lean on what the project already depends on** before writing your own
  implementation or adding a package. Do not assume a library lacks a
  capability without reading its documentation and types.
- Custom implementations here are usually deliberate and measured — the VAD,
  the endpointer, the token batcher, the chunker. Read
  `docs/decisions/no-dart-audio-engine.md` before reaching for a package to
  replace one.
- Fallbacks and migrations are not clutter to be removed. The half-duplex
  path exists because hardware varies; the storage migrations exist so a
  conversation survives an upgrade.

## Measuring

- **A number from a harness is not a number from the product.** Reproduce it
  in the app, through the real model and the whole path, before believing
  it. A standalone benchmark said 1.4s and the app said nothing, and both
  were right — about different languages.
- **Check the instrument before believing a negative result.** Feed it a case
  whose answer is not in doubt. Smart Turn v3.2 was rejected only after a
  recording cut in the middle of a word also scored 0.98, which is what
  distinguishes a saturated model from an undecided one.
- Measurements that changed a decision belong in `docs/decisions/`, with the
  numbers and the machine they came from, so the next person argues with the
  evidence rather than re-running it.

## Window architecture (measured — do not re-litigate without new measurements)

- The desktop window is **one stage** shared by both forms (orb / conversation),
  never larger than the conversation: a titled window answers the mouse across
  its whole frame regardless of what it draws, so any empty margin would stand
  as an invisible wall over the desktop.
- **Never resize** the engine-hosting window programmatically — a resize blocks
  until the engine returns a frame at the new size (~1.004s timeout). Moving
  the origin is free; the collapse glide is origin-only.
- Click routing on see-through windows is decided by the **window server** from
  drawn alpha (borderless) or the whole frame (titled). The orb's clicks are
  carried by `OrbInputPanel`, which draws a 1%-alpha circle. The Flutter
  gesture layer on `DesktopOrbSurface` exists **for accessibility** — real
  clicks never reach it.
- The RunnerTests host is the real app with the real user settings; `main.dart`
  switches to the fake runtime under `XCTest*` env vars. Keep that guard.
- Full screen: the panel enters it only with `isFloatingPanel = false` and
  `.fullScreenPrimary`. While full screen, the window's frame belongs to the
  system — never set it. Geometry follows the frame and reaches Dart via
  `onPresentationGeometryChanged`.
- One centred content column (`ConversationContentColumn`, max 820pt, margin
  24pt) holds the title bar, the turns and the composer; their leading edges
  must always agree. The title bar sits below the traffic-light line with
  28pt clearance.
- Windowed test suites (integration tests and RunnerTests) hang before the
  first frame whenever the **current Space is another app's full-screen
  Space**: a `.fullScreenPrimary` window may not appear there, so the engine
  never gets a frame. Switch to a normal desktop Space before running the
  gate. Diagnose with `defaults read com.apple.spaces` (Current Space type 4).
