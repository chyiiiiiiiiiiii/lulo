# Security

Lulo's promise is that a conversation stays on the Mac it happened on. A bug
that breaks that promise is a security bug, even when nothing crashes.

## Reporting

Report privately through GitHub's **Report a vulnerability** button on the
repository's Security tab. Please do not open a public issue for anything in
the list below. You should hear back within a week.

## What counts

- Anything that sends conversation text, audio, a screenshot, a calendar
  event, or a remembered fact off the machine, other than the paths listed
  under *What leaves the machine* in [README.md](README.md).
- A way for text the model reads — a document, a tool result, a selection
  passed in through the Services menu — to get written into the agent's
  memory, or to make the agent take an action the user did not ask for.
  [docs/decisions/memory-is-an-attack-surface.md](docs/decisions/memory-is-an-attack-surface.md)
  describes the boundary that is supposed to prevent this.
- Anything that lets the sandboxed app read or write outside its container
  beyond the folders the user picked through the system panel.
- A sidecar in `sidecars/` that listens on anything other than loopback.

## Not in scope

- What the model says. It is a 4B-parameter model running on a laptop, and
  it is wrong in ordinary ways; that is a quality bug, and a normal issue is
  the right place for it.
- The model files themselves, which are downloaded from Hugging Face and
  governed by Google's Gemma terms.
