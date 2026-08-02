#!/usr/bin/env python3
"""Build a Qwen shadow candidate from an existing ASR candidate."""

from __future__ import annotations

import argparse
import copy
import json
import pathlib
import urllib.request
from collections.abc import Callable

DEFAULT_ENDPOINT = "http://127.0.0.1:46559/v1/refine"


def refine_candidate(
    source: dict[str, object],
    vocabulary: list[str],
    propose: Callable[[dict[str, object]], dict[str, object]],
) -> dict[str, object]:
    if source.get("schemaVersion") != 1 or source.get("kind") != "transcript":
        raise ValueError("input must be a schema v1 transcript candidate")
    cases = source.get("cases")
    if not isinstance(cases, list):
        raise ValueError("input must be a schema v1 transcript candidate")
    result = copy.deepcopy(source)
    result["runId"] = f'{source.get("runId", "unknown")}-qwen-shadow'
    output_cases = result["cases"]
    assert isinstance(output_cases, list)
    provider: dict[str, str] | None = None
    for case in output_cases:
        if not isinstance(case, dict):
            raise ValueError("invalid transcript candidate case")
        case_id = _required_string(case, "caseId")
        raw = _required_string(case, "rawTranscript")
        request = {
            "schemaVersion": 1,
            "requestId": f"golden-{case_id}",
            "locale": "zh-TW",
            "rawTranscript": raw,
            "protectedVocabulary": list(vocabulary),
        }
        response = propose(request)
        if (
            response.get("schemaVersion") != 1
            or response.get("requestId") != request["requestId"]
        ):
            raise ValueError(f"case {case_id}: invalid sidecar response")
        case["refinedTranscript"] = _required_string(response, "refinedTranscript")
        identity = {
            "name": _required_string(response, "providerId"),
            "version": _required_string(response, "providerVersion"),
        }
        if provider is not None and identity != provider:
            raise ValueError("sidecar identity changed during run")
        provider = identity
    if provider is None:
        raise ValueError("transcript candidate has no cases")
    result["adapter"] = provider
    return result


def _required_string(value: dict[str, object], key: str) -> str:
    field = value.get(key)
    if not isinstance(field, str) or not field.strip():
        raise ValueError(f"invalid {key}")
    return field


def _http_proposer(endpoint: str) -> Callable[[dict[str, object]], dict[str, object]]:
    if not endpoint.startswith(("http://127.0.0.1:", "http://[::1]:")):
        raise ValueError("endpoint must use a literal loopback host")

    def propose(payload: dict[str, object]) -> dict[str, object]:
        request = urllib.request.Request(
            endpoint,
            data=json.dumps(payload, ensure_ascii=False).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            value = json.load(response)
        if not isinstance(value, dict):
            raise ValueError("sidecar response must be an object")
        return value

    return propose


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--endpoint", default=DEFAULT_ENDPOINT)
    parser.add_argument("--vocabulary", action="append", default=[])
    args = parser.parse_args()
    output = pathlib.Path(args.output)
    if output.exists():
        parser.error("output already exists")
    source = json.loads(pathlib.Path(args.input).read_text())
    if not isinstance(source, dict):
        parser.error("input root must be an object")
    result = refine_candidate(source, args.vocabulary, _http_proposer(args.endpoint))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
