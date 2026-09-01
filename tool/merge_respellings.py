#!/usr/bin/env python3
"""Fold a `grow_respellings.py` report into the shipped table and corpus.

The report is machine-made and this is where a person decides what to keep,
so the filter is written out rather than implied:

  * an entry needs a sentence, and the sentence it was measured on goes into
    the corpus with it -- an entry nothing can re-render is one nobody can
    delete after a model upgrade;
  * `--sentence-broken-only` keeps just the entries where the *sentence* was
    wrong, which is the strong evidence. Without it, entries whose sentence
    was already fine come too: those are real defects that a recogniser with
    context repaired, which is how 訓練 was nearly missed, and they are also
    how 字串 would have been wrongly added. Choose deliberately;
  * nothing is kept whose respelling is already a word in the table, or
    whose length differs, because the shipped tests refuse both anyway and
    failing here says why;
  * an entry that would be **misread inside a longer word** is dropped. The
    table has no segmenter and does not need one while every entry preserves
    the sound, but 行業 -> 形業 also fires inside 五金行業, where 行 is háng;
  * a **mainland-only word** is dropped. A frequency-ranked word list comes
    from a mainland dictionary, so it carries words this agent would never
    say -- 報道 where Taiwan writes 報導 -- and the recogniser's own Taiwan
    conversion rewrites them, which scores the voice down for something it
    did not do. The test is `s2tw(word) != s2twp(word)`: character
    conversion and phrase conversion disagreeing is exactly what "Taiwan
    says this differently" means.

    python3 tool/merge_respellings.py report.json [--sentence-broken-only]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACKAGE = ROOT / "sidecars" / "pronunciation"
sys.path.insert(0, str(PACKAGE))

from lexicon import RESPELLINGS  # noqa: E402

try:
    from candidates import misread_inside_a_longer_word
except ImportError:  # noqa: BLE001 - the shipped test catches it either way
    misread_inside_a_longer_word = None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report")
    parser.add_argument("--sentence-broken-only", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    arguments = parser.parse_args()

    report = json.loads(pathlib.Path(arguments.report).read_text())
    existing_respellings = {value[0] for value in RESPELLINGS.values()}
    try:
        from opencc import OpenCC
        to_simplified = OpenCC("tw2s").convert
        taiwanise = OpenCC("s2twp").convert

        def taiwan_says(word: str) -> str:
            # The word list was already converted to Traditional, so the
            # phrase table has nothing to match. Going back to Simplified
            # first is what makes 報道 -> 報導 visible and leaves 領導 alone.
            return taiwanise(to_simplified(word))
    except ImportError:
        taiwan_says = None

    keep: list[dict[str, object]] = []
    for entry in report.get("entries", []):
        word, said = str(entry["word"]), str(entry["saidAs"])
        why = None
        if word in RESPELLINGS:
            why = "already in the table"
        elif len(word) != len(said):
            why = "changes the number of syllables"
        elif said in RESPELLINGS:
            why = "its respelling is itself a word in the table"
        elif said in existing_respellings:
            why = "another word already respells to it"
        elif not entry.get("sentence"):
            why = "no sentence to re-render it in"
        elif taiwan_says is not None and taiwan_says(word) != word:
            why = f"Taiwan says {taiwan_says(word)}, so nobody would say this"
        elif misread_inside_a_longer_word is not None and (
                broken := misread_inside_a_longer_word(word, said, limit=1)):
            longer, got, wanted = broken[0]
            why = (f"inside {longer} it would say {got} where {wanted} is "
                   f"needed — the table has no segmenter")
        elif arguments.sentence_broken_only and not entry.get("sentenceWasBroken"):
            why = "the sentence was already fine"
        if why:
            print(f"  skip {word} -> {said}: {why}")
            continue
        keep.append(entry)
        existing_respellings.add(said)

    print(f"\n{len(keep)} of {len(report.get('entries', []))} entries kept")
    if arguments.dry_run or not keep:
        return 0

    lexicon = PACKAGE / "lexicon.py"
    text = lexicon.read_text()
    marker = "\n}\n"
    end = text.index(marker, text.index("RESPELLINGS: dict"))
    rows = "".join(
        f'    "{e["word"]}": ("{e["saidAs"]}", '
        f'"{str(e["before"]).replace("這個詞是", "").strip("。 ")}", '
        f'"{e["word"]}"),\n'
        for e in keep
    )
    lexicon.write_text(text[:end] + "\n" + rows.rstrip("\n") + text[end:])

    corpus = PACKAGE / "corpus.py"
    text = corpus.read_text()
    anchor = 'MIXED: tuple[tuple[str, str], ...] = ('
    insert = text.index(anchor)
    grown = "# Found and measured by `grow_respellings.py`, sentence and all.\n"
    grown += "GROWN: dict[str, str] = {\n"
    grown += "".join(f'    "{e["word"]}": "{e["sentence"]}",\n' for e in keep)
    grown += "}\n\n\n"
    text = text[:insert] + grown + text[insert:]
    text = text.replace(
        "        *IN_A_SENTENCE.values(),",
        "        *IN_A_SENTENCE.values(),\n        *GROWN.values(),", 1)
    text = text.replace(
        '    "found-in-a-sentence": """',
        '    "grown": """' + " ".join(str(e["word"]) for e in keep)
        + '""",\n    "found-in-a-sentence": """', 1)
    corpus.write_text(text)
    print(f"lexicon.py and corpus.py updated; run the package's tests next")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
