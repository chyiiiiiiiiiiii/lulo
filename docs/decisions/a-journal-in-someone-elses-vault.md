# A journal in someone else's vault

**Status:** built, off by default.
`packages/agent_core/lib/src/obsidian/obsidian_journal.dart` (the format),
`lib/features/obsidian/obsidian_journal_writer.dart` (the mirror),
`macos/Runner/ObsidianVault.swift` (the grant and the write).

Lulo can append every finished exchange to a page in the user's own Obsidian
vault. The premise is not backup and it is not sync. It is this:

> A year from now, with Lulo uninstalled, the questions and the answers are
> still in the user's notes, in Markdown, beside the rest of their thinking.

Everything below follows from taking that literally.

## Append only, and never rewrite

The file is **in somebody else's vault**. They may have edited it, linked to
it, tagged it, or written three paragraphs of their own underneath it. A tool
that rewrites the file destroys that work, and destroys it silently — the user
finds out later, if ever.

So nothing already on disk is ever touched. `ObsidianVault.append` creates the
file when it is missing and otherwise seeks to the end and writes.

What that costs, stated plainly:

- A regenerated answer lands **beside** the one it replaced, not over it.
- A question rewound with `dropFromLastQuestion` **stays**.
- A conversation renamed in Lulo does not rename anything in the vault.

That is what a journal is, and it is the right trade for a record whose whole
value is that it can be trusted not to change under you.

## One page a day, not one a conversation

The obvious design is a note per conversation. It was rejected on file naming.

A conversation's title is not immutable — the user renames it, and Lulo
renaming their note behind them breaks whatever they linked to it from. Keeping
the name fixed while the title moves means keeping an index of which note
belongs to which conversation, somewhere, forever, and an index is a thing that
goes stale: delete it and the next write silently starts a duplicate note.

A **day** is an immutable fact. `2026-08-28.md` never has to change, no index
has to exist, and there is nothing to go stale. It is also the shape every
daily-note plugin already uses, so the page lands where the user is already
looking.

## The question is the heading

The obvious feature is a model-written summary. That was rejected on cost and
on premise.

Cost: a summary per turn is a whole extra generation in a runtime with **one
generation slot**, which is the same slot the next question needs
(see [`the-model-will-not-interrupt-itself-to-remember.md`](the-model-will-not-interrupt-itself-to-remember.md)).
Premise: a summary is lossy, in a file whose point is that nothing is lost.

The question the user actually asked is a summary that costs nothing and
cannot be wrong. It becomes the heading, so a year of pages is scannable in
Obsidian's own outline. A question too long to be a heading is cut there — by
graphemes, so a family emoji does not end up half a surrogate pair in someone's
notes — and repeated whole underneath, because the page has to be a better
record than the app it outlives.

A conversation-level summary, written **once** when a conversation has gone
quiet and appended like everything else, is the natural next step and does not
break any of the rules above. It is not built.

## The vault never decides whether a turn is stored

`ObsidianJournalWriter` is a decorator over `ConversationStorageService`. Every
method delegates **first** and mirrors afterwards, and every failure out
there — a dead network share, a deleted folder, a revoked grant, an exception
of any kind — is recorded and otherwise ignored.

Losing the app's own record of a conversation because somebody's Dropbox was
unmounted would be a far worse failure than not mirroring it.

Only **completed** answers are filed. A cancelled or failed turn is a decision
the user made or a fault they watched happen, not something to keep in their
notes for a year — and a journal that cannot retract must not write what it
would want to take back.

It is a decorator rather than a hook inside `ConversationRepository` because
the app has to be able to run without it at all: with no window host there is
nothing to write through, and the composition root then simply does not wrap.
Nothing downstream knows it is there.

## A path is not permission

The app is sandboxed. An Obsidian vault lives wherever the user keeps it, which
is outside the container, so the folder is reachable only through a grant an
`NSOpenPanel` issued — and that grant has to be kept as a **security-scoped
bookmark** or it is gone at the next launch.

`ObsidianVault` therefore stores the bookmark and never a path, and Settings
**asks** for the current folder rather than remembering one. A vault can be
moved, renamed or deleted while the app is not looking; a remembered string
would show the user a folder that cannot actually be opened, which is exactly
the failure this is meant to make visible. A stale bookmark that still resolves
is re-issued on the spot, or the grant expires behind the user.

`startAccessingSecurityScopedResource()` returning false is **not** a refusal:
it also answers false for a URL that needs no scope at all, such as anything
inside the app's own container. Reading it as denial reported writes that were
about to succeed as permission failures. It decides only whether the scope has
to be handed back. "Nobody chose a folder" and "the folder they chose is gone"
stay different answers, because Settings tells the user different things about
the two.

Writing happens off the main thread. A vault on a synced or network volume must
never make a turn wait.

`ObsidianVaultTests` runs the real `FileManager` and `FileHandle` path against
a real folder, because every other test of this feature stands behind a fake
host — and "built and never connected to anything" is exactly what a fake host
cannot catch. The load-bearing one is
`testWhatTheUserWroteThemselvesIsNeverTouched`.

## Off by default

An absent settings key is not consent. Writing into someone's vault is a larger
permission than most of the app's: the folder is outside the container, the
files are ones they may have written in themselves, and the whole point is that
what lands there outlives this app. The switch only appears once a folder has
been chosen — a switch that turns on a mirror with nowhere to write is a switch
that does nothing — and choosing a folder turns it on, because choosing one is
asking for this.

Settings shows how the **last** write went. A mirror that has quietly stopped
working is worse than one that was never turned on: the user believes their
thinking is being kept somewhere it is not.
