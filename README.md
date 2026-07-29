# Lulo

A local conversation agent for macOS. It rests on your desktop as a small
drifting orb and opens into a conversation when you call it with
<kbd>⌘⇧Space</kbd>. Nothing it says leaves the machine.

## Where the name came from

Over a bowl of 滷肉飯 — *lǔ ròu fàn*, braised pork rice, the most ordinary
lunch in Taiwan. Say the first syllable out loud and most of a name is
already there.

Looking it up afterwards, `lulo` turns out to be Albanian for **flower**. Not
a translation of anything intended, just a coincidence worth keeping: a small
thing that opens when you come to it and closes again when you leave.

Which is roughly what this is. Most of the time Lulo is a quiet orb in the
corner of the screen, drifting at the display's own refresh rate and
answering to nobody. Ask for it and it comes.

## What it is

- **Local.** The model runs on this Mac. There is no network path for a
  conversation to take.
- **Resident.** Lulo does not launch and quit. It sits on the desktop across
  every Space, above other work, and never takes the caret from whatever you
  are typing into.
- **One presence, two forms.** The orb and the conversation are the same
  agent. Collapsing throws it back to its corner rather than swapping one
  widget for another: the same orb, moved, still keeping its own clock.

## Running it

```sh
flutter pub get                       # from the repository root — it is a workspace
cd apps/local_agent_macos
flutter run -d macos
```

That gives you the deterministic fake runtime: one fixed reply, no model, no
network. It is what the tests and the preview run against, so a canned answer
is the runtime working rather than the model failing.

For the real model, point the build at a LiteRT-LM file:

```sh
flutter run -d macos \
  --dart-define=INFERENCE_RUNTIME=litert \
  --dart-define=LOCAL_MODEL_PATH=/path/to/gemma-4-E4B-it.litertlm
```

## Verification

The whole gate, from the repository root:

```sh
dart run tool/verify.dart
```

Formatting, analysis, the Dart and Flutter tests, the macOS integration test
against a real window, a profile build, and the Swift tests. It always runs
everything and reports every failure rather than stopping at the first.

## Two things that were measured rather than guessed

Both times the measurement contradicted what the screen appeared to show, and
both are guarded by tests now.

**The window never changes size.** Changing form used to stall for exactly
1.004 seconds. A number that round is a timeout, not work: resizing a window
that hosts the Flutter engine blocks until the engine returns a frame at the
new size, on the thread the engine needs in order to make one. So both forms
are drawn inside one stage that keeps its size for the life of the app, and
it answers the mouse only where it is actually drawn, so clicks clear of the
agent reach whatever is behind it.

**Arrival is set by the damped frequency, not by the decay.** The orb is
thrown between its two places on a spring. When it arrived too slowly, the
obvious fix — damping it harder so it settles sooner — made it worse, because
damping lowers the frequency that decides when it gets there. Speed came from
stiffness instead. A test steps the simulation and fails if the agent takes
too long to be home, so that mistake cannot come back quietly.
