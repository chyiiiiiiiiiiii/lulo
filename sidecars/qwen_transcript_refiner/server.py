#!/usr/bin/env python3
"""Loopback-only Qwen transcript proposal sidecar for Lulo development."""

from __future__ import annotations

import argparse
import dataclasses
import json
import logging
import re
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import BinaryIO, Protocol

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 46559
DEFAULT_MODEL = "mlx-community/Qwen3-0.6B-4bit"
MAX_REQUEST_BYTES = 32 * 1024
MAX_TRANSCRIPT_CHARS = 8_000
MAX_VOCABULARY_ITEMS = 128
MAX_VOCABULARY_CHARS = 128
PROVIDER_ID = "qwen-mlx-transcript-refiner"
PROVIDER_VERSION = "1"

_REQUEST_FIELDS = frozenset(
    {
        "schemaVersion",
        "requestId",
        "locale",
        "rawTranscript",
        "protectedVocabulary",
    }
)


class ProtocolError(ValueError):
    """A safe client-visible protocol failure without transcript contents."""


@dataclasses.dataclass(frozen=True)
class ProposalRequest:
    request_id: str
    locale: str
    raw_transcript: str
    protected_vocabulary: tuple[str, ...]


def decode_request(stream: BinaryIO, content_length: int) -> ProposalRequest:
    if content_length <= 0:
        raise ProtocolError("empty request")
    if content_length > MAX_REQUEST_BYTES:
        raise ProtocolError("request too large")
    try:
        value = json.loads(stream.read(content_length))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ProtocolError("invalid JSON request") from error
    if not isinstance(value, dict):
        raise ProtocolError("request must be an object")
    unknown = set(value) - _REQUEST_FIELDS
    if unknown:
        raise ProtocolError("unknown fields are not accepted")
    if set(value) != _REQUEST_FIELDS or value.get("schemaVersion") != 1:
        raise ProtocolError("invalid request envelope")
    request_id = _bounded_string(value, "requestId", 128)
    locale = _bounded_string(value, "locale", 16)
    transcript = _bounded_string(value, "rawTranscript", MAX_TRANSCRIPT_CHARS)
    vocabulary = value.get("protectedVocabulary")
    if not isinstance(vocabulary, list) or len(vocabulary) > MAX_VOCABULARY_ITEMS:
        raise ProtocolError("invalid protected vocabulary")
    terms: list[str] = []
    for term in vocabulary:
        if not isinstance(term, str) or not term.strip() or len(term) > MAX_VOCABULARY_CHARS:
            raise ProtocolError("invalid protected vocabulary")
        terms.append(term)
    if locale != "zh-TW":
        raise ProtocolError("unsupported locale")
    return ProposalRequest(request_id, locale, transcript, tuple(terms))


def parse_content_length(value: str | None) -> int:
    try:
        length = int(value or "0")
    except ValueError as error:
        raise ProtocolError("invalid content length") from error
    if length < 0:
        raise ProtocolError("invalid content length")
    return length


def _bounded_string(value: dict[str, object], key: str, limit: int) -> str:
    field = value.get(key)
    if not isinstance(field, str) or not field.strip() or len(field) > limit:
        raise ProtocolError(f"invalid {key}")
    return field


def build_prompt(request: ProposalRequest) -> str:
    vocabulary = json.dumps(
        request.protected_vocabulary, ensure_ascii=False, separators=(",", ":")
    )
    transcript = json.dumps(request.raw_transcript, ensure_ascii=False)
    return f"""你是臺灣華語逐字稿校正器。只修正明顯的辨識錯字、標點、大小寫與下列專有詞，不改變語意、不擴寫、不回答內容。
請使用臺灣繁體中文。原句若出現專有詞的大小寫或明顯同音變體，改成清單中完全相同的拼法；若原句已正確，原樣回傳。
必須只輸出單一 JSON 物件，格式為 {{"refinedTranscript":"..."}}，不得解釋或加入其他欄位。
專有詞：{vocabulary}
逐字稿：{transcript}"""


def extract_refinement(output: str) -> str:
    candidate = output.strip()
    fenced = re.fullmatch(r"```(?:json)?\s*(.*?)\s*```", candidate, re.DOTALL)
    if fenced:
        candidate = fenced.group(1)
    try:
        value = json.loads(candidate)
    except json.JSONDecodeError as error:
        raise ProtocolError("invalid model response") from error
    if not isinstance(value, dict) or set(value) != {"refinedTranscript"}:
        raise ProtocolError("invalid model response")
    refined = value.get("refinedTranscript")
    if not isinstance(refined, str) or not refined.strip() or len(refined) > MAX_TRANSCRIPT_CHARS:
        raise ProtocolError("invalid model response")
    return refined


class ProposalEngine(Protocol):
    def propose(self, request: ProposalRequest) -> str: ...


class MlxQwenEngine:
    """Loads one MLX model and serializes generation to bound memory usage."""

    def __init__(self, model_id: str) -> None:
        from mlx_lm import generate, load
        from mlx_lm.sample_utils import make_sampler

        self._model, self._tokenizer = load(model_id)
        self._generate = generate
        self._sampler = make_sampler(temp=0.0)
        self._lock = threading.Lock()

    def propose(self, request: ProposalRequest) -> str:
        messages = [{"role": "user", "content": build_prompt(request)}]
        prompt = self._tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=True,
            enable_thinking=False,
        )
        with self._lock:
            output = self._generate(
                self._model,
                self._tokenizer,
                prompt=prompt,
                max_tokens=256,
                sampler=self._sampler,
                verbose=False,
            )
        return extract_refinement(output)


def make_handler(engine: ProposalEngine) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "LuloTranscriptRefiner/1"

        def do_GET(self) -> None:  # noqa: N802
            if self.path != "/health":
                self._write_json(HTTPStatus.NOT_FOUND, {"error": "not found"})
                return
            self._write_json(
                HTTPStatus.OK,
                {"status": "ready", "providerId": PROVIDER_ID, "providerVersion": PROVIDER_VERSION},
            )

        def do_POST(self) -> None:  # noqa: N802
            started = time.monotonic()
            request_id = "unknown"
            if self.path != "/v1/refine":
                self._write_json(HTTPStatus.NOT_FOUND, {"error": "not found"})
                return
            try:
                length = parse_content_length(self.headers.get("Content-Length"))
                request = decode_request(self.rfile, length)
                request_id = request.request_id
                refined = engine.propose(request)
                self._write_json(
                    HTTPStatus.OK,
                    {
                        "schemaVersion": 1,
                        "requestId": request.request_id,
                        "refinedTranscript": refined,
                        "providerId": PROVIDER_ID,
                        "providerVersion": PROVIDER_VERSION,
                    },
                )
                logging.info("proposal ok request_id=%s elapsed_ms=%d", request_id, (time.monotonic() - started) * 1000)
            except ProtocolError as error:
                logging.warning("proposal rejected request_id=%s reason=%s", request_id, error)
                self._write_json(HTTPStatus.BAD_REQUEST, {"error": str(error)})
            except Exception:
                logging.exception("proposal failed request_id=%s", request_id)
                self._write_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": "proposal failed"})

        def log_message(self, format: str, *args: object) -> None:
            logging.info("http client=%s status=%s", self.client_address[0], args[1] if len(args) > 1 else "unknown")

        def _write_json(self, status: HTTPStatus, value: dict[str, object]) -> None:
            body = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    return Handler


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=DEFAULT_HOST, choices=("127.0.0.1", "::1"))
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    engine = MlxQwenEngine(args.model)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(engine))
    logging.info("ready host=%s port=%d provider=%s version=%s", args.host, args.port, PROVIDER_ID, PROVIDER_VERSION)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
