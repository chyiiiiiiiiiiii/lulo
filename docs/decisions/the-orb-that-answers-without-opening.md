# The orb that answers without opening

**Status:** built, **off by default** — Settings › 你的桌面 › Buttons under
the resting orb. The three actions all pass the test below; the person it was
built for looked at it on their own desktop and said the situations where they
would reach for it do not really come up. That is the more important
measurement, and it is not one the test could have made. Kept rather than
deleted because the argument and the tests are the expensive parts and both
survive being switched off, and because the strip is still the only place the
microphone can be opened without summoning the window — if a use turns up, it
is a switch away.

`macos/Runner/OrbActionStrip.swift`,
`macos/Runner/DesktopPanelController.swift` (`OrbInputPanel`,
`OrbCatcherView`), `packages/agent_core/lib/src/presence/orb_actions.dart`,
`lib/app/app.dart` (`_askTheConversation`, `_refreshOrbActions`).

Hovering the resting orb raises a small capsule of buttons beside it. This
records why there is one at all, why there are three buttons and not eight,
and why AppKit draws them.

## Was a strip even the right idea

The question worth asking first is whether a resident voice agent needs
buttons. The honest answer is that it needs a very few, and the test that
separates them is narrow:

> **An action earns a place only if doing it any other way costs a summon.**

Everything the user can reach by opening the window — a new conversation, the
settings, the history, a question about the clipboard — fails that test. It
would arrive as a second menu bar drawn on the desktop, which is a worse menu
bar than the one already in the menu bar.

Three things pass it.

| | Otherwise | Why it passes |
|---|---|---|
| **Talk** | ⌘⇧Space, then find the microphone | The conversation stays mounted while the orb rests, so the ears can open **without the window coming back**. That is the difference between an assistant living on the desktop and a window that happens to be small. Nothing else in the app could do this. |
| **Look** | Summon, find the eye in the composer, press it, ask | One press instead of three. It does bring the window back, because the answer is written, not spoken, and an answer nobody can see is not one. |
| **Stop** | Summon and press stop | Interrupting by voice only works while the microphone is open. An answer being read aloud to a resting orb is exactly when the user has no window to stop it in. |

So: yes to a strip, and no to a launcher. The list is expected to stay this
short. Something that only saves a *click* does not belong here; something
that saves a *summon* might.

## Why the positions never move

`orbActionsFor` returns a fixed order and `stop` appears at the **end** rather
than pushing to the front, even though it is the urgent one. A button that
moves under the pointer between one hover and the next cannot be learned, and
being learnable is the whole reason to prefer this to the menu bar, which is
always in the same place and always fully populated.

Nothing at all is offered without a model. An orb whose microphone opens onto
something that cannot answer is worse than an orb that offers nothing, because
the failure arrives *after* the user has spoken.

## Why AppKit draws it

This is forced, not chosen.

`DesktopPanelController.orbRect(inStage:)` places the orb's 168pt square at
`frame.minY` — the very bottom edge of the stage's frame. There is no room
inside the window beneath the orb to draw anything, and
[`AGENTS.md`](../../AGENTS.md) forbids the obvious fix: resizing the
engine-hosting window blocks until the engine returns a frame at the new size,
about a second.

So the strip is drawn into `OrbInputPanel` — the borderless panel that already
exists to catch the orb's clicks — and its **words come from Dart**, exactly as
`HostMenuBarLabels` does for the status-bar menu. AppKit has no localizations
of its own, and a strip that stayed English on a Chinese Mac would be the one
part of the app that did not.

Only the identifier travels back. What `talk`, `look` and `stop` *mean* is
decided in `app.dart` and carried out by `ConversationView`, which is the only
thing that knows whether an ear is already open or an answer is still running.

## Where it stands, and why it flips

`OrbActionStrip.layout` is a pure function of the orb's rectangle and the
screen's visible frame, tested without a window for the same reason
`transitionGeometry` is.

The gap is measured from **where the orb stops painting** — the same 0.725 the
silhouette integration test reads off the real shader — not from the square it
is drawn into. Measuring from the square would leave the capsule floating a
visible distance from an orb that ended long before it.

It goes **under** the orb, unless there is not enough screen left there, and
then **over** it. That is not an edge case: the orb's home is the lower
trailing corner, `orbMargin = 32` from the bottom, so the common case is the
one with no room. A strip that only ever went downwards would spend most of its
life off the bottom of the display.

## The click routing, which is where this could go quietly wrong

Read the **Click routing** section of [`presence.md`](../features/presence.md)
first. The rule that matters: the window server decides who owns a click on a
see-through borderless window from the **alpha it actually draws**.

That rule is what makes the strip safe. The catcher panel now grows to hold
both the orb and the capsule, but while the strip is not showing it still
draws only the orb's 1%-alpha circle — so the rectangle where the capsule
*would* be is not claimed, and the desktop underneath answers the mouse
normally. A resident assistant must not be in the way of anything, and it is
in the way of nothing more than it was before.

While the strip **is** showing, the capsule and the path to it are claimed as
well. The gap between the orb's circle and the capsule is drawn by nobody, and
a gap the window server hands to the desktop is a gap the pointer disappears
into on its way to the buttons — `mouseExited` fires, the strip vanishes, and
it can never be reached.

The first version claimed the **whole panel** for that, and it was measurably
visible. The tint has to be drawn to exist at all, so wherever it is the only
thing on a pixel it is a real step of about **3/255**: sampled off a real
capture against a flat sky, rows inside the panel but clear of everything drawn
had a luminance spread of 4 where the sky's own gradient gave 1. Narrowed by
`OrbCatcherView.bridge(from:to:)` to a rectangle no wider than the capsule and
reaching only to the orb's centre, the same rows read 1 — the step is still
there, but only under a capsule that is already there.

## The dwell

`OrbActionStrip.dwell = 0.25s`. A strip that appeared the instant the pointer
crossed the orb would fire every time the user swept past it on the way to
something else, which — the orb living in a corner of the screen — is most of
the times a pointer is anywhere near it.

## What is not done

- **VoiceOver** reaches the buttons through `accessibilityChildren` on the
  catcher, which is thinner than the Flutter semantics path the orb itself has.
  The same three actions are also in the status-bar menu, which is fully
  accessible.
- The capsule is drawn with `windowBackgroundColor` rather than a real
  `NSVisualEffectView`. Vibrancy would look more like macOS; it is one more
  moving part in a panel whose drawn alpha decides click routing.
