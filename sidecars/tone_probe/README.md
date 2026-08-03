# Tone probe

Deciding whether one Taiwan Mandarin voice is better than another, with
numbers rather than impressions.

The complaint this was built for: the agent's voice "sounds a little off on
some nouns and some characters". That is a real defect and an unfalsifiable
sentence. This package turns it into two measurements a machine can take.

## What it measures

**Did the word survive.** Render `這個詞是X。`, send it back through
Whisper, and check whether X came back. The carrier is the whole trick: it
supplies grammar and no meaning, so the recogniser has nothing to repair a
mispronunciation from and writes down what it heard. On the resident voice,
`這個詞是企業。` came back as `这个词是奇幼` — four carrier characters
perfect, the word under test destroyed. That is the complaint, caught
automatically.

**What tone was actually spoken.** Track the pitch across the syllable
under test and classify its contour against the four tones. This is the
only way to separate qì yè from qǐ yè, because both are the right word and
a recogniser writes both down as 企業.

## What it does not measure

Be suspicious of these numbers in exactly these places.

- **Intelligibility is not correctness.** A word said with the mainland
  reading is still that word, and Whisper transcribes it happily. The ASR
  round trip catches mispronunciation bad enough to destroy a word and is
  blind to a systematically foreign accent.
- **The tone classifier is comparative, not calibrated.** Its thresholds
  separate canonical contours; they were not fitted to labelled Taiwanese
  speech. The four control probes exist to say how much to trust a given
  run, and **every report must be read with its control score attached**.
  A run scoring 2/4 on controls is an instrument problem, not a voice.
- **Syllable boundaries are found by energy, not by alignment.** Mandarin
  syllables run together, and the segmenter refuses rather than guessing
  when it cannot find a real valley — a render that lost a syllable is
  reported as unreadable, not scored. Word-level forced alignment would be
  better and is the obvious next improvement.
- **Isolated words are not the stimulus.** A cloning model handed two
  characters is far outside its training: 檸檬 alone came back as 3.28
  seconds containing three bursts. Everything is rendered in the carrier.

## Layout

| File | What |
|---|---|
| `probes.py` | The words under test and the reading Taiwan expects. |
| `tone.py` | Pitch contour to tone. Pure, no audio. |
| `pitch.py` | Pitch tracking and syllable spans. numpy only. |
| `measure.py` | One rendered probe, measured. |
| `scoring.py` | Did the word survive the round trip. |

Nothing here loads a model or opens an audio device. The scripts that do
live in the `lulo-tts` sidecar repository: `render_probes.py` writes WAV
files, `score_probes.py` reads them back. Rendering and recognition run in
separate virtualenvs because the two models do not share dependencies.

## Probe categories

- `control` — one unambiguous word per tone. If these fail, stop.
- `taiwan-reading` — where Taiwan and the mainland disagree about the same
  spelling: 企業, 危險, 攜帶, 液體, 曝光, 垃圾, 星期, 品質, 蝸牛. Each
  records both readings, so a failure can say *which* standard was spoken.
- `polyphone` — 破音字, always in pairs (銀行/行動, 音樂/快樂). A single
  probe would let a model that memorised one reading look correct.
- `sandhi` — 一 and 不, the most frequent words in the language.
- `tech-noun` — what an agent says about its own work.

## Running

```sh
# in ~/dev/lulo-tts, the rendering virtualenv
python render_probes.py --backend sidecar --label qwen3-ryan --out /tmp/p/qwen3
python render_probes.py --backend mlx --label indextts --out /tmp/p/indextts \
    --repo models/indextts-1.5 --ref-audio voices/ryan.wav

# in the recogniser virtualenv
source .venv-ears/bin/activate
python score_probes.py --run /tmp/p/qwen3 --run /tmp/p/indextts --out /tmp/p/report.json
```

Neither script opens an audio device. Rendering writes WAV files and
nothing is ever played.

## Tests

```sh
python3 -m unittest discover
```

Runs on the workspace gate. The instrument that decides which voice ships
has to be as trustworthy as the thing it measures, and it is the kind of
code that rots invisibly: a segmenter that quietly stops finding syllables
still returns a number, and the number still looks like a result.
