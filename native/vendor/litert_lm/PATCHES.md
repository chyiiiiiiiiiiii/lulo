# LiteRT-LM v0.14.0 local package

This directory is a narrow, auditable macOS package derived from the official
[`google-ai-edge/LiteRT-LM`](https://github.com/google-ai-edge/LiteRT-LM)
release `v0.14.0`, Git revision
`80f301ff9a3b02c2c1e7be2dd1a567752f7b51b6`, under Apache-2.0.

Only the ten production Swift wrapper sources from upstream `swift/` and the
upstream `LICENSE` are copied, with the narrow local wrapper patch documented
below. Upstream tests, iOS artifacts, repository
history, build caches, model files, and binary archives are intentionally not
vendored. The deterministic wrapper-source hash is
`147c61bff2e672d4ccd6e8f00b62d77f2bebd0db071f52fd3dcc30baa4f27e81`,
computed by hashing each source with SHA-256, sorting those records by
filename, and hashing the resulting records. The opt-in verification gate also
pins every individual source hash and the license hash.

## Local patches

1. The official macOS archive URL is retained, but its checksum is corrected
   from upstream's invalid
   `13e818c9d3987afa87f0716884ebf0b6b10677b480717b8b098146e6b4f45847`
   to the independently verified archive checksum
   `450615483509aaa6d34b321fdc6862e41a224b674468ab10aff64ebe113d21b7`.
2. The upstream `-Xlinker -all_load` unsafe linker flag is omitted. With Swift
   6.3.3 and Xcode 26.6 it creates 54 duplicate Swift compatibility symbols;
   omitting only that flag compiles, links, and runs the no-model smoke.
3. `Conversation.sendMessageStream` and its internal `sendToStream` path accept
   a validated per-call `maxOutputTokens` and pass it to
   `litert_lm_conversation_optional_args_set_max_output_tokens`. Values must be
   positive and fit in `Int32`; invalid values throw the typed
   `LiteRTLMError.conversation(.invalidMaxOutputTokens)` instead of being
   ignored. Model-free Swift tests pin propagation, omission, and validation.
4. `Engine.createConversation` returns `sending Conversation` instead of a bare
   `Conversation`. `Engine` is an actor and `Conversation` is a non-`Sendable`
   class, so under Swift 6 strict concurrency the value cannot otherwise cross
   the actor boundary to the caller. `sending` transfers the only reference out
   of the actor's isolation domain and lets the compiler prove no aliasing
   remains behind, which keeps the LiteRT `Conversation` confined to one
   isolation domain at a time. Marking `Conversation` `@unchecked Sendable` is
   deliberately rejected: it would silence the compiler while leaving the
   underlying `CConversationHandle` reachable concurrently, which is exactly
   the data race this project's actor-per-generation ownership model prevents.

The local manifest is scoped to the macOS product and production wrapper, so
the unused upstream iOS binary and upstream test targets are not reproduced.
The binary's minimum supported deployment target is macOS 12.0.

## Binary cache and offline use

The first SwiftPM resolution downloads the official compressed macOS archive
(approximately 43 MB) and expands it into the consuming package's ignored
`.build/artifacts` cache (approximately 132 MB). Repeated builds are offline
and deterministic while that cache remains present. No binary, archive, build
cache, or model is committed.

From the workspace root, run the opt-in provenance, resolution, compile, link,
and no-model gate with:

```sh
CI=true DART_SUPPRESS_ANALYTICS=true \
  dart run tool/verify_litert_lm_vendor.dart
```

## Exit condition

Return to the official package when a released LiteRT-LM manifest both declares
the verified macOS archive checksum and links the Swift wrapper without
`-all_load` duplicate symbols on the project's supported Swift/Xcode toolchain.
At that point, replace the local path dependency with the exact fixed upstream
version and delete this directory.
