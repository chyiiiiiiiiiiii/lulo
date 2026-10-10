# Lulo

A local conversation agent for macOS. It rests on your desktop as a small
drifting orb and opens into a conversation when you call it with
<kbd>⌘⇧Space</kbd>. The model runs on your Mac, and so does everything you
say to it.

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

- **Local.** Gemma 4 runs in-process through
  [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM). There is no
  server, no account, and no API key.
- **Resident.** Lulo does not launch and quit. It sits on the desktop across
  every Space, above other work, and never takes the caret from whatever you
  are typing into.
- **One presence, two forms.** The orb and the conversation are the same
  agent. Collapsing throws it back to its corner rather than swapping one
  widget for another: the same orb, moved, still keeping its own clock.
- **Spoken to, not only typed at.** Hold <kbd>⌘⇧Space</kbd> to talk. While
  it answers, 「對對對」 is heard as agreement and 「不對」 stops it — turn-taking
  is decided by the words, not by how long you spoke.
- **Bilingual.** It opens in English; Taiwan Mandarin is a switch in
  Settings, and the interface follows the language of your Mac.

It can also search your past conversations, look up real places, read your
calendar when you ask about your schedule, take one look at your screen when
you press the eye button, answer from a document you open, and pick up text
you select in another app through **Services › Ask Lulo about this**. Memory,
sharing the name of the app you are in, and a daily journal written into
your own Obsidian vault are all **off** until you turn them on.

## Requirements

- Developed and tested on Apple Silicon with macOS 26. Intel Macs have not
  been tried.
- **macOS 26** for voice — listening uses `SpeechAnalyzer`. Typing works
  without it.
- macOS 14 for the screen look (ScreenCaptureKit).
- Flutter **3.47.1** (Dart `^3.12.0`), which CI pins.
- About 3.7 GB of disk for the recommended model.

## Running it

```sh
flutter pub get                       # from the repository root — it is a workspace
cd apps/local_agent_macos
flutter run -d macos
```

With no model installed, Lulo opens on a first-run screen that downloads one.
**Gemma 4 E4B** is recommended; E2B is smaller and faster. 12B gives the
strongest answers and is offered last on purpose: on an M1 Pro it took a
minute to load and 17 seconds to its first token. Models are fetched
from [`litert-community`](https://huggingface.co/litert-community) on Hugging
Face and are governed by Google's Gemma terms, not by this repository's
license.

## Voice: what is and is not in this repository

Lulo's voice comes from two local servers that live **outside** this
repository and are not published here:

| Port | What | Without it |
|---|---|---|
| `46557` | The speaking voice (Qwen3-TTS) | Lulo answers in text and stays quiet |
| `46558` | The batch recogniser for the hold key | The hold key uses the streaming transcript, which is less accurate |

Settings shows which of the two is reachable. Listening itself, the
endpointer, interruption, and everything else about a spoken turn are in this
repository and work without either.

The `sidecars/` directory holds the parts that *are* here: the pronunciation
table the voice reads (214 measured respellings for words a small TTS model
says wrongly in Taiwan Mandarin), and the measurement tools behind several
decisions in [`docs/decisions/`](docs/decisions/).

## What leaves the machine

The conversation, your voice, screenshots, calendar events and anything the
agent remembers stay on your Mac. Three things do not:

- **Model downloads** come from huggingface.co.
- **Speech recognition assets** are downloaded by macOS the first time a
  language is used; recognition itself runs on-device.
- **Place searches** go to Apple Maps. When you ask for somewhere — a quiet
  café in 台中 — the model writes a search query and the system's own local
  search sends it, the same path your Maps searches take. No location is
  attached. This tool is always available.

Calendar access is read-only and asked for the first time you need it;
screen recording is asked for the first time you press the eye button.

## Verification

The whole gate, from the repository root:

```sh
dart run tool/verify.dart
```

Formatting, analysis with every lint fatal, the Dart, Flutter, Python and
Swift tests, two integration tests against a real window, a profile build,
and static checks on the built bundle and on the entitlements a release is
signed with. It always runs everything and reports every failure rather than
stopping at the first. Quit any running Lulo first — a live instance with the
same bundle identifier makes the window tests hang.

## Documentation

[`docs/README.md`](docs/README.md) is the reading map: the architecture, one
document per feature, and the decisions that were measured rather than
guessed, with the numbers and the machine they came from.

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

## License

MIT — see [LICENSE](LICENSE). LiteRT-LM is vendored under Apache-2.0 with its
local patches listed in
[`native/vendor/litert_lm/PATCHES.md`](native/vendor/litert_lm/PATCHES.md);
the aurora shader is ported from ChunUI and webgl-noise under MIT. Both are
reproduced in the app's
[`ThirdPartyNotices.txt`](apps/local_agent_macos/macos/Runner/ThirdPartyNotices.txt).
Security reports: see [SECURITY.md](SECURITY.md).
