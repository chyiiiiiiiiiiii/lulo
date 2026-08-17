# The companion that watches: measured, staged, and mostly not yet

The ask under review: Lulo lives on the desktop — can it understand what
the user is doing, on screen, in real time, and speak up with help at the
right moment? A friend to talk to, an assistant at hand, and an agent that
notices.

The short answer this document argues: **the north star is right, the
always-watching version of it is wrong on this machine and mostly wrong as
a product, and there is a staged path that delivers the felt experience —
"it saw what I meant" — without building the part that fails.** One stage
of it became buildable tonight, by measurement.

## What was measured tonight

The model this app already ships can see. `gemma-4-E4B-it`'s artifact
carries a vision encoder, the runtime loads it behind an engine flag, and
the vendored Swift wrapper exposes the whole surface —
`EngineConfig(visionBackend:)`, `Content.imageFile` — so nothing needs
re-vendoring. Probed through the pip binding on this M1 Pro: a real
3024×1964 screenshot, downscaled to 896 px, described in Traditional
Chinese in **7.6 s** —

> 這張截圖展示了在 macOS 系統上開啟的 LINE 應用程式介面，其中一個視窗正在
> 顯示 LINE 的登入畫面。背景中可以看到桌面上排列著多個應用程式的圖示和文件。

Structurally right (macOS, windows, desktop icons), wrong in a detail (no
LINE login was on that screen), one sample. Read it as: **a look costs
about eight seconds and is roughly, not reliably, right.**

Three structural facts follow from numbers this repo already holds:

1. **A look is a generation.** The runtime holds one generation slot; a
   look blocks a voice turn the way any turn does. Continuous watching
   would keep the machine permanently busy at ~8 s a frame and make the
   conversational agent — the product that exists — worse to fund a
   feature that does not.
2. **Watching the screen is macOS's heaviest permission.** Screen
   Recording TCC covers every pixel of every app: passwords momentarily
   visible, patient records, other people's messages. This repo already
   set its doctrine on such asks when it refused Accessibility for
   Services write-back: *not a permission this app should ask for to save
   two steps*. It can be asked for a feature the user explicitly invokes;
   it must not be the price of installing a chat app.
3. **Proactive voice is the most expensive interruption there is.** The
   endpointer work in this repo measures pauses in fractions of a second
   because talking over someone is that costly — and that is when they
   are already in conversation. Speaking up unprompted while they work is
   the same act with no invitation at all.

## What the comparable products actually do

Stated from general knowledge of these projects; verify details before
citing numbers from them.

- **Rewind / screenpipe** (the second one open source) record the screen
  continuously and answer questions over the recording. They are honest
  about what they are — a recorder is the product, disk and battery are
  the price, and the TCC ask is front and center at setup. Lulo is not a
  recorder, and bolting continuous capture onto a companion would import
  the price without the product.
- **Open Interpreter / computer-use agents** act on the screen — they
  need Accessibility and synthetic input, the exact pair this repo
  already rejected for Services write-back. Acting is a different
  product with a different risk envelope.
- **Highlight, Cluely, and the copilot-overlay family** converge on the
  same interaction grammar from different directions: **summoned, not
  interrupting** — a hotkey or a glanceable surface, context gathered at
  the moment of summons. That convergence is evidence about users, not
  fashion.
- **Clippy** is the canonical proof that noticing plus interrupting reads
  as surveillance plus condescension, and it failed with far lower
  stakes than a microphone-holding, screen-reading resident agent.
- **macOS itself**: `NSWorkspace.frontmostApplication` is free of any
  permission and says which app the user is in. Window titles and
  contents are not free. The OS draws the privacy line between "which
  app" and "what's in it", and that line is a good default for Lulo too.

The pattern taken from all of it: **context on summons, glanceable
presence, never unprompted voice.** The one thing Lulo already has that
none of them do is the orb — a resident, ambient surface that can show
"I might be useful" without saying a word.

## The staged path

**Stage 0 — context without permission.** What the app can know for free:
the frontmost app's name, the clock it already tells, the document the
user already opened, the selection Services already deliver. Putting the
frontmost app into the turn instruction the way the clock goes in — a few
tokens, read at compose time — lets 「我卡住了」 mean something without a
single new permission. Cheap, useful, and honest about its limits.

**Stage 1 — the invited look.** 「看一下我的螢幕」: a button or hotkey the
user presses, one screenshot, one vision message, one answer. The 8 s
latency fits an invited action; the TCC ask happens at the feature, in
plain words, the way this app asks for the microphone. This is buildable
now — the measurement above is its feasibility study — and it is the
right first vision feature because the user's finger on the key *is* the
consent, the scope, and the timing, all three problems solved by the
interaction shape instead of by policy.

**Stage 2 — noticing without speaking.** If a trigger fires — app switch,
long idle in one place, an error dialog pattern — the orb changes, and
nothing else happens. The user glances or doesn't. Opening it shows what
Lulo noticed and would offer. Voice never initiates; text never pops
over the work. This stage needs Stage 1's permission plus real trigger
design, and it should be measured against the only test that matters:
does the user open it, or learn to ignore it? That test is now written
down as budgets and tripwires the app enforces on itself, fixed before
any Stage 2 code —
[an-ignored-light-stays-ignored.md](an-ignored-light-stays-ignored.md).

**Non-goals, written down so they stay decided:** continuous capture or
recording (a different product with a different price), acting on the
screen via synthetic input (already-rejected permission pair), and
unprompted voice (the one way to make a companion unwelcome). Any of
these can be revisited by a future measurement, not by drift.

## 文字還是聲音

Layered, matching who started the exchange. The orb is for what Lulo
noticed (it costs no attention until glanced at); text is for what the
user summoned while working (it waits); voice is for conversation the
user is already having. The mode of the *answer* follows the mode of the
*ask* — the app's existing rule, extended to a presence that can now have
something to say first.

## What this unblocks tomorrow

Stage 0 shipped the morning after this was written:
`NSWorkspace.didActivateApplicationNotification` pushed over Pigeon,
gated by Settings › 你的桌面 (off by default), joining the turn half
beside the clock. Stage 1 shipped the same day: an eye button in the
composer takes one screenshot of the whole display with Lulo's own
windows excluded (ScreenCaptureKit, macOS 14+, downscaled at capture),
attaches it to the question — the field's words, or a default "what am I looking at" — and
the runtime answers with the vision executor the shipped E4B already
carried. Measured on this stack before building: enabling vision costs
~0.5 s at engine load and nothing on text turns; a look is ~5.7 s end to
end. The TCC ask happens inside the first press, which is the whole
design: the tap is the consent, the scope, and the timing. Each capture
deletes the previous look's file — the app keeps no archive of the
user's screen. Aiming the capture at "the front window of the app the
user came from" was the first design and its first real use refuted it:
the last activation belonged to a menu-bar utility whose only window is
an invisible black panel, and the look came back a black rectangle — a
guessed window is a heuristic, and what 「我的螢幕」 means is what the
eyes see. The 12B question stays closed — the look runs on the
model already installed, and 17 s more per look would not buy a better
glance.
