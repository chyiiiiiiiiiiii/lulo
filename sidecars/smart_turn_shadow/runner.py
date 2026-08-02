#!/usr/bin/env python3
"""Run Pipecat Smart Turn against Lulo's private voice-eval corpus."""

from __future__ import annotations

import argparse
import copy
import json
import pathlib
import time
from collections.abc import Callable

MODEL_REPO = "pipecat-ai/smart-turn-v3"
MODEL_FILE = "smart-turn-v3.2-cpu.onnx"


def build_shadow_candidate(
    baseline: dict[str, object],
    predict: Callable[[str], tuple[bool, int]],
    *,
    vad_silence_ms: int,
) -> dict[str, object]:
    if (
        baseline.get("schemaVersion") != 1
        or baseline.get("kind") != "turn"
        or not isinstance(baseline.get("cases"), list)
    ):
        raise ValueError("input must be a schema v1 turn candidate")
    if vad_silence_ms < 0:
        raise ValueError("vad silence must not be negative")
    result = copy.deepcopy(baseline)
    result["runId"] = f'{baseline.get("runId", "unknown")}-smart-turn-v3.2-shadow'
    result["adapter"] = {"name": "pipecat-smart-turn", "version": "3.2-cpu"}
    cases = result["cases"]
    assert isinstance(cases, list)
    for case in cases:
        if not isinstance(case, dict):
            raise ValueError("invalid turn candidate case")
        case_id = _required_string(case, "caseId")
        segments = case.get("speechSegments")
        if not isinstance(segments, list) or not segments:
            raise ValueError(f"case {case_id}: missing speech segments")
        final_segment = segments[-1]
        if not isinstance(final_segment, dict) or not isinstance(
            final_segment.get("endMs"), int
        ):
            raise ValueError(f"case {case_id}: invalid speech segments")
        complete, inference_ms = predict(case_id)
        if inference_ms < 0:
            raise ValueError(f"case {case_id}: invalid inference latency")
        case["candidateSubmitAtMs"] = (
            final_segment["endMs"] + vad_silence_ms + inference_ms
            if complete
            else None
        )
    return result


def _required_string(value: dict[str, object], key: str) -> str:
    field = value.get(key)
    if not isinstance(field, str) or not field.strip():
        raise ValueError(f"invalid {key}")
    return field


class SmartTurnPredictor:
    def __init__(self) -> None:
        import onnxruntime as ort
        from huggingface_hub import hf_hub_download
        from transformers import WhisperFeatureExtractor

        options = ort.SessionOptions()
        options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        options.inter_op_num_threads = 1
        options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        model_path = hf_hub_download(repo_id=MODEL_REPO, filename=MODEL_FILE)
        self._session = ort.InferenceSession(model_path, sess_options=options)
        self._extractor = WhisperFeatureExtractor(chunk_length=8)

    def predict(self, audio_path: pathlib.Path) -> tuple[bool, int]:
        import librosa
        import numpy as np

        started = time.monotonic()
        audio, _ = librosa.load(audio_path, sr=16_000, mono=True)
        audio = audio[-8 * 16_000 :].astype(np.float32)
        inputs = self._extractor(
            audio,
            sampling_rate=16_000,
            return_tensors="np",
            padding="max_length",
            max_length=8 * 16_000,
            truncation=True,
            do_normalize=True,
        )
        features = np.expand_dims(
            inputs.input_features.squeeze(0).astype(np.float32), axis=0
        )
        probability = self._session.run(None, {"input_features": features})[0][
            0
        ].item()
        elapsed_ms = round((time.monotonic() - started) * 1000)
        return probability > 0.5, elapsed_ms


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--corpus", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--vad-silence-ms", type=int, default=200)
    args = parser.parse_args()
    output = pathlib.Path(args.output)
    if output.exists():
        parser.error("output already exists")
    baseline = _read_object(pathlib.Path(args.baseline))
    corpus_path = pathlib.Path(args.corpus)
    corpus = _read_object(corpus_path)
    raw_cases = corpus.get("cases")
    if not isinstance(raw_cases, list):
        parser.error("invalid corpus cases")
    audio_by_case = {
        _required_string(case, "id"): corpus_path.parent
        / _required_string(case, "audioPath")
        for case in raw_cases
        if isinstance(case, dict)
    }
    predictor = SmartTurnPredictor()

    def predict(case_id: str) -> tuple[bool, int]:
        audio = audio_by_case.get(case_id)
        if audio is None or not audio.is_file():
            raise ValueError(f"case {case_id}: private audio missing")
        return predictor.predict(audio)

    result = build_shadow_candidate(
        baseline, predict, vad_silence_ms=args.vad_silence_ms
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")


def _read_object(path: pathlib.Path) -> dict[str, object]:
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError(f"{path.name}: root must be an object")
    return value


if __name__ == "__main__":
    main()
