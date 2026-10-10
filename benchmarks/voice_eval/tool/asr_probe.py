#!/usr/bin/env python3
"""Run an MLX Whisper checkpoint over a corpus and write candidate JSON.

The comparison this exists for is narrow: `~/dev/lulo-tts/ears.py` serves the
push-to-talk path with `mlx-community/whisper-large-v3-turbo`, and
Breeze-ASR-25 claims to be better at exactly the two things this corpus
measured as its worst real errors — Taiwanese Mandarin and Mandarin-English
code-switching.

Both models are run through the same post-processing `ears.py` applies, so
what is compared is the path the app would actually take and not two raw
model outputs.

Run: python3 asr_probe.py <model-repo> <adapter-name> <out.json>
              [corpus.json] [language|auto]

The corpus and the decode language are arguments because `ears.py` pins
`language="zh"` on the live path, so "can this model hear English" and "can
the shipped configuration hear English" are two different questions.
"""

from __future__ import annotations

import json
import os
import sys
import time
import wave
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
DEFAULT_CORPUS = REPO / "benchmarks/voice_eval/corpus/zh-TW-v1.json"
# `lang` lives in the voice sidecar, which is not part of this repository.
sys.path.insert(0, os.environ.get("LULO_TTS_DIR", str(Path.home() / "dev/lulo-tts")))

import mlx_whisper  # noqa: E402
from lang import held_prompt, tidy_transcript  # noqa: E402
from opencc import OpenCC  # noqa: E402

_to_traditional = OpenCC("s2twp").convert

# The vocabulary the app hands the recogniser. Same list, so the comparison
# is of models and not of how much help each was given.
TERMS = [
    "Lulo", "Flutter", "Dart", "Gemma", "LiteRT",
    "Qwen", "MLX", "Swift", "Xcode", "Claude", "Codex",
]


def duration_ms(path: Path) -> int:
    with wave.open(str(path), "rb") as handle:
        return int(handle.getnframes() / handle.getframerate() * 1000)


def main() -> int:
    repo, adapter, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    corpus = Path(sys.argv[4]) if len(sys.argv) > 4 else DEFAULT_CORPUS
    language = sys.argv[5] if len(sys.argv) > 5 else "zh"
    audio_root = corpus.parent
    manifest = json.loads(corpus.read_text())

    print(f"loading {repo} …", flush=True)
    warm = time.monotonic()
    mlx_whisper.transcribe(
        str(audio_root / manifest["cases"][0]["audioPath"]), path_or_hf_repo=repo
    )
    print(f"warm in {time.monotonic() - warm:.1f}s", flush=True)

    cases = []
    for case in manifest["cases"]:
        path = audio_root / case["audioPath"]
        if not path.exists():
            print(f"missing {path}")
            continue
        began = time.monotonic()
        options = {
            "path_or_hf_repo": repo,
            "initial_prompt": held_prompt(TERMS),
        }
        if language != "auto":
            options["language"] = language
        result = mlx_whisper.transcribe(str(path), **options)
        elapsed = time.monotonic() - began
        text = tidy_transcript(_to_traditional(str(result["text"]).strip()))
        cases.append(
            {
                "caseId": case["id"],
                "rawTranscript": text,
                "refinedTranscript": None,
                "partialEvents": [],
                "finalAtMs": int(elapsed * 1000),
            }
        )
        print(
            f"{case['id']:<28}{elapsed:>6.2f}s  "
            f"rtf {elapsed / (duration_ms(path) / 1000):>4.2f}  {text}",
            flush=True,
        )

    Path(out_path).write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "runId": f"{adapter}-{int(time.time())}",
                "corpusId": manifest["corpusId"],
                "kind": "transcript",
                "adapter": {
                    "name": adapter,
                    "version": f"{repo} language={language}",
                },
                "cases": cases,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    print(f"\nwrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
