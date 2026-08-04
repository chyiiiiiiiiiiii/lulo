# Taiwan Mandarin voice candidates — raw probe data

The per-probe results behind the summary tables in
[`../../../../docs/decisions/taiwan-mandarin-voice-candidates.md`](../../../../docs/decisions/taiwan-mandarin-voice-candidates.md).
Kept because that document quotes four numbers and these are the thirty-seven
each of them was averaged from — a table can be argued with, a percentage
cannot.

| File | Run |
|---|---|
| `report-2.json` | The resident voice, Qwen3-TTS 0.6B 8bit |
| `report-voxcpm2.json` | VoxCPM2 4bit at its default ten inference steps |
| `report-voxfast.json` | VoxCPM2 4bit at four steps — the only setting that keeps up with playback |
| `report-bf16.json` | Qwen3-TTS unquantised, which is how quantisation was ruled out as the cause |

Each holds the recogniser used, and per run its real-time factor, audio
seconds, and for every probe word whether it survived being said and read
back. `lostIds` is the list that matters: the words the voice turned into
different words.

No personal data. Every waveform these describe was synthesised from a probe
list, and the audio itself is not kept — it is reproducible from
`~/dev/lulo-tts/render_probes.py` while the candidate models stay cached, and
nothing in the conclusions depends on hearing it again.
