#!/usr/bin/env python3
"""Run an MLX Whisper checkpoint over the corpus and write candidate JSON.

The comparison this exists for is narrow: `~/dev/lulo-tts/ears.py` serves the
push-to-talk path with `mlx-community/whisper-large-v3-turbo`, and
Breeze-ASR-25 claims to be better at exactly the two things this corpus
measured as its worst real errors — Taiwanese Mandarin and Mandarin-English
code-switching.

Both models are run through the same post-processing `ears.py` applies, so
what is compared is the path the app would actually take and not two raw
model outputs.

Run: python3 asr_probe.py <model-repo> <adapter-name> <out.json>
"""

from __future__ import annotations

import json
import sys
import time
import wave
from pathlib import Path

REPO = Path("/Users/you/dev/flutter_local_agent")
CORPUS = REPO / "benchmarks/voice_eval/corpus/zh-TW-v1.json"
AUDIO = CORPUS.parent
sys.path.insert(0, "/Users/you/dev/lulo-tts")

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
    manifest = json.loads(CORPUS.read_text())

    print(f"loading {repo} …", flush=True)
    warm = time.monotonic()
    mlx_whisper.transcribe(
        str(AUDIO / manifest["cases"][0]["audioPath"]), path_or_hf_repo=repo
    )
    print(f"warm in {time.monotonic() - warm:.1f}s", flush=True)

    cases = []
    for case in manifest["cases"]:
        path = AUDIO / case["audioPath"]
        if not path.exists():
            print(f"missing {path}")
            continue
        began = time.monotonic()
        result = mlx_whisper.transcribe(
            str(path),
            path_or_hf_repo=repo,
            language="zh",
            initial_prompt=held_prompt(TERMS),
        )
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
                "adapter": {"name": adapter, "version": repo},
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
