# Qwen transcript refiner sidecar

Developer-only, loopback-only shadow proposals for finalized `zh-TW`
transcripts. The App never uses these proposals as live conversation input.

## Setup

```bash
cd sidecars/qwen_transcript_refiner
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python server.py
```

The first launch downloads `mlx-community/Qwen3-0.6B-4bit` (about 335 MB)
from Hugging Face. Later launches use the local cache. The service binds to
`127.0.0.1:46559` and exposes:

- `GET /health`
- `POST /v1/refine`

Enable the App-side shadow explicitly when launching Flutter:

```bash
flutter run -d macos \
  --dart-define=TRANSCRIPT_SHADOW_ENDPOINT=http://127.0.0.1:46559/v1/refine
```

No conversation history, memory, profile, or previous transcript is accepted
by the protocol. Logs contain request IDs and timing only, never transcript
text or protected vocabulary.

## Checks

```bash
python3 -m unittest test_server.py
python3 -m py_compile server.py
```
