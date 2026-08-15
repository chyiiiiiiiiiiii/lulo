# LiteRT-LM v0.16.0 local package

This directory is a narrow, auditable macOS package derived from the official
[`google-ai-edge/LiteRT-LM`](https://github.com/google-ai-edge/LiteRT-LM)
release `v0.16.0`, Git revision
`924e79c91542761242244e4f1651851f822e4cbb`, under Apache-2.0.

Only the eleven production Swift wrapper sources from upstream `swift/` and
the upstream `LICENSE` are copied, with the narrow local wrapper patches
documented below. Upstream tests, the `apple_fm` adapter, iOS artifacts,
repository history, build caches, model files, and binary archives are
intentionally not vendored. The deterministic wrapper-source hash is
`3e1ec1ee0fe86600a14bafae1b72c5f6189d4288d1070079ab2a147b5f2f3730`,
computed by hashing each source with SHA-256, sorting those records by
filename, and hashing the resulting records. The opt-in verification gate also
pins every individual source hash and the license hash.

The v0.14.0 vendoring carried two patches that upstream has since made
unnecessary and are gone from this copy: the archive checksum correction
(upstream's v0.16.0 manifest declares the checksum this package verified
independently, `3ae6c876abd74614b1869bfc40cb4d0b892981363564740268b1f8ac5cf895a4`)
and the `-all_load` omission (upstream's manifest no longer passes it).

Why this vendoring did not simply end there, given both original reasons are
resolved: depending on the upstream package by Git URL clones an ~877 MB
repository into every cold SwiftPM cache, where this package costs one 46 MB
binary archive — and two of the local patches below are still required for
this project to compile and to work at all. Revisit when upstream publishes a
registry package or a manifest-only distribution.

## Local patches

1. `Conversation.sendMessage`/`sendMessageStream` validate the per-call
   `maxOutputTokens` before the C boundary via
   `applyConversationMaxOutputTokens`. Upstream converts with a bare
   `Int32(_:)`, which traps at runtime on overflow and silently accepts zero
   and negative values; invalid values throw the typed
   `LiteRTLMError.conversation(.invalidMaxOutputTokens)` instead. Model-free
   Swift tests pin propagation, omission, and validation.
2. `Engine.createConversation` returns `sending Conversation` instead of a
   bare `Conversation`. `Engine` is an actor and `Conversation` is a
   non-`Sendable` class, so under Swift 6 strict concurrency the value cannot
   otherwise cross the actor boundary to the caller. `sending` transfers the
   only reference out of the actor's isolation domain and lets the compiler
   prove no aliasing remains behind. Marking `Conversation`
   `@unchecked Sendable` is deliberately rejected: it would silence the
   compiler while leaving the underlying `CConversationHandle` reachable
   concurrently, which is exactly the data race this project's
   actor-per-generation ownership model prevents.
3. The streaming path honors `automaticToolCalling`. Upstream checks the flag
   in the synchronous `sendMessage` and ignores it in `streamCallback`, so a
   streaming caller could never take the model's tool calls and run the tools
   itself. With the flag off, pending calls are yielded as a `Message`
   carrying `toolCalls` and the stream finishes — the same contract the
   synchronous path keeps. (`Conversation.automaticToolCalling` becomes
   `fileprivate` so the file-scope callback can read it, the way it already
   reaches `handleToolCalls`.)
4. `ConversationConfig` accepts `toolDeclarationsJson`, tool declarations
   given directly as OpenAPI JSON, preferred by `Engine.createConversation`
   over the schema generated from Swift tool types. The `[Tool]` path
   requires a Swift type per tool with a static name, which a tool defined at
   runtime on the far side of a message channel cannot have. Pair with
   `automaticToolCalling: false`; execution belongs to the caller.

The local manifest is scoped to the macOS product and production wrapper, so
the unused upstream iOS binary, the `apple_fm` adapter, and upstream test
targets are not reproduced. The binary's minimum supported deployment target
is macOS 12.0.

## Binary cache and offline use

The first SwiftPM resolution downloads the official compressed macOS archive
(approximately 46 MB) and expands it into the consuming package's ignored
`.build/artifacts` cache. Repeated builds are offline and deterministic while
that cache remains present. No binary, archive, build cache, or model is
committed.

From the workspace root, run the opt-in provenance, resolution, compile, link,
and no-model gate with:

```sh
CI=true DART_SUPPRESS_ANALYTICS=true \
  dart run tool/verify_litert_lm_vendor.dart
```

## Exit condition

Return to the official package when the patches above are upstream (or
upstream's equivalents make them unnecessary) **and** depending on it no
longer costs a full repository clone per cold cache — a registry package or
manifest-only distribution. The original v0.14.0 exit conditions (a declared
checksum that verifies, a manifest without `-all_load`) are both met as of
v0.16.0 and are no longer what keeps this directory alive.
