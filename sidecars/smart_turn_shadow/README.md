# Smart Turn shadow runner

Runs the BSD-2-Clause Pipecat Smart Turn v3.2 CPU model against Lulo's
private Taiwan Mandarin corpus. It produces `kind: turn` candidate evidence
only and cannot call the production endpoint.

Smart Turn expects 16 kHz mono audio and evaluates up to the final eight
seconds of the current turn. This runner invokes it after a configurable VAD
silence interval (200 ms by default), then includes measured local inference
time in the candidate timestamp.

## Setup and run

```bash
cd sidecars/smart_turn_shadow
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python runner.py \
  --baseline /tmp/lulo-baseline-turn.json \
  --corpus ../../benchmarks/voice_eval/corpus/zh-TW-v1.json \
  --output /tmp/smart-turn-v3.2-shadow.json
```

The first run downloads the 8 MB quantized ONNX checkpoint. The baseline
candidate supplies measured speech segments, today's 800 ms submission, and
the human-authored expected window. Missing private audio fails the run; it is
never replaced by generated speech.

Public v3.2 results are encouraging overall, but the published Chinese subset
is weaker than the aggregate result. Keep this shadow-only until Lulo's own
Taiwan Mandarin corpus shows no premature submissions and an acceptable
miss rate, especially on thinking pauses and self-corrections.

## Checks

```bash
python3 -m unittest discover
python3 -m py_compile runner.py
```
