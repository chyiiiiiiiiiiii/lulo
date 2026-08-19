# Qwen refiner shadow — the LLM polish is a net loss

The question: can an LLM refiner repair the full-duplex recogniser's zh
transcript after the fact? The `qwen_transcript_refiner` sidecar existed but
had never been scored. This run scores it, twice.

Input was `../full-duplex-through-the-file/candidate-full-duplex-zh.json`
(Apple `SpeechTranscriber`, locale zh-TW), refined through the sidecar with
the ten-term `builtInVocabulary` as the protected list, on the standard
prompt. A rejected or malformed proposal falls back to the raw text, which is
what production does. Scored by `tool/evaluate.dart` against `zh-TW-v1`.

| Candidate | heard CER | spoken CER | median latency (warm) |
|---|---:|---:|---:|
| raw (no refinement) | **6.04%** | **14.64%** | — |
| Qwen3-0.6B-4bit | 7.62% | 16.21% | ~315ms |
| Qwen3-4B-4bit | 10.46% | 18.64% | ~1.2s |

Both models made the transcript **worse**, and bigger was worse than smaller.
Not because of noise — because of what each chose to touch:

- **Neither fixed a single target error.** `NLX`, `Dortest` and (for 4B)
  `Flater` all survived, with the correct spellings sitting in the protected
  vocabulary the prompt carried. These are exactly the code-switching errors
  the refiner exists for.
- **0.6B hallucinated a correction**: `Flater` → `Lulo`, a protected term,
  the wrong one. It also emitted a simplified character (`检查`) against an
  explicit zh-TW instruction, and failed the JSON format outright on one
  short input.
- **4B resolved a self-correction backwards**: 「我想看明天哎不是後天的天氣」
  became 「我想看明天的天氣」 — the user corrected themselves *to* 後天, and
  the model kept 明天. A CER point is the least of that error; it inverts
  what the user asked for. It also "fixed" 還沒 to 還未, which was not broken.
- The only genuine repair in either run was 4B's 隻是 → 只是. One character,
  against everything above.

The pattern is the one `SpokenVocabularyBook` already recorded from the other
side: these errors are phonetic neighbours of the true words, and repairing
them needs the *sound*, which the refiner does not have. A text-only LLM
guesses, and a guess that lands on a fluent sentence is undetectable
downstream — the same property that made the raw errors hard to catch makes
the hallucinated repairs worse.

What the errors do have is structure: `Flater`→`Flutter`, `NLX`→`MLX`,
`Dortest`→`Dart test` are all near-matches of protected vocabulary. A
deterministic phonetic-similarity substitution against that list could fix
exactly these with no power to invent anything — the same family as
`AgentProfile.misheard`, which already cannot fail this way.

Reproduce: `sidecars/qwen_transcript_refiner/server.py` (optionally
`--model mlx-community/Qwen3-4B-4bit`), then the fallback runner semantics
above, then `evaluate.dart`. The refined candidates and both reports are in
this directory.
