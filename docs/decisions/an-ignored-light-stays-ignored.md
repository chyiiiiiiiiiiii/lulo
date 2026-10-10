# An ignored light stays ignored

**State:** criteria fixed, then built. This file was written before the
first line of Stage 2 code, on purpose; `PresenceNoticeCenter`
(`apps/local_agent_macos/lib/features/presence/notice/`) implements it and
landed in the same commit.
[the-companion-that-watches.md](the-companion-that-watches.md) gave the
stage one test — *does the user open it, or learn to ignore it?* — and
this document turns that sentence into definitions, budgets and tripwires
that the app enforces on itself. Code that implements Stage 2 implements
this file. The numbers here move by measurement, not while debugging.

## Why the gate is written first

Because this feature's failure mode is irreversible in a way this repo's
other failures are not. A wrong answer can be corrected on the next turn; a
slow answer can be made faster; but a user who has learned that the light
means nothing stops looking, and there is no mechanism — no redesign, no
better trigger — that reliably wins the glance back. Notification fatigue
is a one-way door: the habit of not-looking survives the fix.

The repo already holds a measured precedent.
[memory-is-an-attack-surface.md](memory-is-an-attack-surface.md) records
that Gemini shows a notification when memory is written **and users do not
read it** — a surface that lights on every write trained its users to skip
it. That is not an argument against a light; it is an argument that the
attention spend has to be budgeted *before* there is any data, because
overspending during the measurement destroys the thing being measured.

So the order is inverted from a normal feature: thresholds first, then
code, then data — and the thresholds are deliberately conservative,
because they can be loosened by evidence but the user's habit cannot be
reset by a settings change.

## The vocabulary the code must implement

Five words, defined so that every count below has an unambiguous
denominator. These are meant to become identifiers.

- **A notice.** A trigger fires, survives the budget, and the orb takes a
  quiet lit state — while the presence is `idle` and the conversation is
  closed, and only then. A trigger firing mid-conversation or mid-answer
  produces no notice: the user is already looking at Lulo, and a light
  competing with an answer is noise. Each notice records its trigger kind
  and timestamp.
- **A glance.** The user opens the orb while the notice is lit. What
  opens is whatever Lulo noticed and would offer — the payload, not a
  generic conversation. Time from lit to opened is recorded.
- **Expiry.** The light goes out on its own after `noticeLifetime` if not
  glanced at. A light that never goes out is not a signal, it is
  furniture — and a permanent light makes every rate below meaningless.
- **Seen-and-ignored.** A notice that expired *while the user was
  demonstrably at the machine* — there was user activity during the lit
  window (an app switch pushed by the Stage 0 channel, input to Lulo, a
  hotkey). This is the count that convicts a trigger.
- **Unseen.** A notice that expired with no evidence anyone was there —
  screen locked, machine idle, user at lunch. Excluded from every
  denominator. An empty chair must not convict a trigger; without this
  distinction, leaving for a meeting twice would mute a kind that was
  never actually ignored.

Everything below is computed **per trigger kind**, because triggers fail
independently: the user deciding that app-switch notices are worthless
says nothing about memory-write notices, and one bad trigger must not be
able to spend the whole feature's credibility.

## The budget — spending limits that precede data

| Knob | Initial value | What it protects |
|---|---|---|
| `noticeLifetime` | 15 minutes | The rates: a light must be able to expire for "ignored" to exist |
| Minimum gap between notices, any kind | 30 minutes | The glance itself: two lights an hour apart is a companion, six is a dashboard |
| Notices per day, all kinds | 4 | The habit: habituation is built in tens of exposures, so the daily spend must be small enough that the tripwires below can fire first |
| Notices per day, one kind | 2 | One noisy trigger exhausting the shared budget |

A trigger that fires over budget — or while the user is already looking
at Lulo, which no light should compete with — is dropped silently and
counted as `suppressed`: visible when debugging, absent from every rate.
Suppression is not failure; it is the budget working.

## The tripwires — what the app does to itself

Evaluated on **seen** notices only (glanced + seen-and-ignored), per kind:

- **Streak.** Five consecutive seen-and-ignored notices → the kind mutes
  itself. It stops lighting entirely until the user re-enables it in
  Settings.
- **Rate.** Over the trailing ten seen notices, fewer than three glances →
  the kind mutes itself. The streak catches fast rejection; the rate
  catches the chronic version where an occasional glance keeps a mostly
  worthless light alive.
- Muting is **silent**. Announcing "I'll stop showing you this" is one
  more interruption spent on a channel the user has just finished saying
  no to. The muted state is visible in Settings, next to the counts that
  caused it.

And the global verdict, written down now so it cannot be renegotiated
later in the heat of wanting the feature to live: **if every kind is
muted, Stage 2 has failed its own test.** The recorded response is to
remove or redesign the triggers — not to raise the thresholds. A
threshold raised so that a light keeps lighting *is* learning to ignore,
performed by the developer on the user's behalf.

What earns the other direction: a kind that survives four weeks unmuted
is worth keeping; a kind glanced at on half or more of its seen notices
is evidence the noticing is wanted, and is the precondition for admitting
any richer trigger. New kinds enter under the same budget and the same
tripwires. No kind is exempt, including the ones that feel obviously
valuable — obviously valuable is what every notification believes about
itself.

## What the numbers cannot say

Single user, counts in the tens. These are tripwires, not statistics —
no confidence intervals will be harmed. Two honesty notes, recorded so
the numbers are read at their real weight:

- **Attribution is soft.** A glance while lit may be coincidence — the
  user was opening Lulo anyway. Two things are recorded rather than
  guessed at: the baseline (opens of the unlit orb per day, which
  already happen today), and time-to-glance, because an open within the
  first minute of lighting is probably caused by it. Neither proves
  causation, and the tripwires do not need it proven: a kind ignored five
  straight times by a present user is failing *whatever* the reason.
- **The activity signal is best-effort.** Seen-versus-unseen leans on the
  Stage 0 app-switch channel — which reports locally whether or not
  `shareFrontmostApp` shares the app's name with the model, and is read
  here for presence evidence only — and on input to Lulo itself. Where
  the evidence is thin, a notice is classed unseen, which errs in the
  trigger's favour, never against it. That is the correct direction for
  the error.

## Where the numbers live

On this machine and nowhere else. A human-readable JSON file beside
`agent_profile.json`, indented, capped to the most recent two hundred
notices — the same file-a-person-can-open-in-an-editor property that
`FileAgentProfileStore` leans on, for the same reason. Settings shows the
per-kind ledger in words — lit, glanced, muted-or-not — which is this
repo's standing pattern for monitoring: not a metric pipeline, a list the
user can read when something feels off.

## The first kind is the memory write

Stage 2's first trigger is not a new watcher. It is the surface the
memory feature shipped without:
[the-model-will-not-interrupt-itself-to-remember.md](the-model-will-not-interrupt-itself-to-remember.md)
writes facts silently, and today the only way to learn what Lulo kept is
to open Settings. A kept memory becomes a notice; glancing shows the
sentence that was stored, who decided (the provenance line the settings
sheet already renders), and the forget button.

This is deliberately **not** a write notification, and the difference is
the whole design. The notification — measured failing in the Gemini
precedent above — demands attention at write time and is skipped; the
notice waits, costs nothing until glanced at, and expires. If the user
never glances memory notices, the kind mutes and the app is exactly where
it is today: silent writes, visible in Settings. Nothing is lost by the
attempt, which is what makes it the right first kind.

It also obeys every number above. Memory writes should be rare —
`rememberFacts` is off by default, and the extraction pass drops ordinary
questions and transient remarks outright (0/20 kept on the probe's
no-fact conditions) — so the budget will seldom bind on this kind. That
is fine. The budget exists for the kinds that come later.

## Non-goals, restated as properties of the light

The stage's non-goals — continuous capture, synthetic input, unprompted
voice — hold and are not restated here. These are the additional ones
that belong to the light itself:

- No sound. No popover. No focus steal. No badge counts. The lit state is
  a change in the orb's own glow and nothing else, and it respects
  reduced motion like every other presence state.
- Ignoring a notice must cost the user nothing, and the app's only
  response to being ignored is to record it and, eventually, to stop.
  **Escalation is the banned response.** A light that gets brighter, or
  blinks, or brings a friend because it was ignored is the Clippy path,
  and the tripwires exist precisely so the app walks the other way.
