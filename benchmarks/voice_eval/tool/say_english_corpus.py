#!/usr/bin/env python3
"""Regenerate the synthetic English corpus audio from its manifest.

The zh-TW corpus is twelve private recordings of one real speaker and its
audio is deliberately never committed. This corpus is different: every case
is macOS `say` output, so the audio is a function of the manifest and there
is nothing personal in it. It is regenerated rather than stored, which keeps
`corpus/audio` meaning the same thing it meant before.

Synthesized speech is cleaner than a person talking. That asymmetry is the
point: a recogniser that fails here fails on real speech too, while one that
passes has only shown an upper bound.

Run: python3 say_english_corpus.py
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

CORPUS = Path(__file__).resolve().parent.parent / "corpus/en-synthetic-v1.json"
VOICE = "Samantha"


def main() -> int:
    manifest = json.loads(CORPUS.read_text())
    root = CORPUS.parent
    for case in manifest["cases"]:
        wav = root / case["audioPath"]
        wav.parent.mkdir(parents=True, exist_ok=True)
        aiff = wav.with_suffix(".aiff")
        subprocess.run(
            ["say", "-v", VOICE, "-o", str(aiff), case["prompt"]], check=True
        )
        # 16 kHz mono, which is what the recognisers take.
        subprocess.run(
            ["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1",
             str(aiff), str(wav)],
            check=True,
        )
        aiff.unlink()
        print(f"{case['id']:<22}{wav}")
    print(f"\n{len(manifest['cases'])} files from {CORPUS.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
