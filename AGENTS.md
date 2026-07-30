# Flutter Local Agent

- Keep `packages/agent_core` pure Dart; it must never import Flutter.
- Follow strict Red/Green TDD for every behavioral change.
- Keep `bootstrap.dart` and future `app_composition.dart` as the composition root.
- Do not add globals, static singletons, or a service locator.
- Run `dart run tool/verify.dart` before a checkpoint commit.

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
