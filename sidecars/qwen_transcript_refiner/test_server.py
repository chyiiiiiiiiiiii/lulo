import io
import json
import unittest

from server import (
    MAX_REQUEST_BYTES,
    ProtocolError,
    build_prompt,
    decode_request,
    extract_refinement,
    parse_content_length,
)


class ProtocolTests(unittest.TestCase):
    def test_decodes_the_bounded_v1_request(self) -> None:
        body = json.dumps(
            {
                "schemaVersion": 1,
                "requestId": "case-1",
                "locale": "zh-TW",
                "rawTranscript": "幫我開啟 Lulo",
                "protectedVocabulary": ["Lulo"],
            }
        ).encode()

        request = decode_request(io.BytesIO(body), len(body))

        self.assertEqual(request.request_id, "case-1")
        self.assertEqual(request.raw_transcript, "幫我開啟 Lulo")
        self.assertEqual(request.protected_vocabulary, ("Lulo",))

    def test_rejects_an_oversized_request_before_reading_it(self) -> None:
        with self.assertRaisesRegex(ProtocolError, "request too large"):
            decode_request(io.BytesIO(b"{}"), MAX_REQUEST_BYTES + 1)

    def test_rejects_history_and_unknown_fields(self) -> None:
        body = json.dumps(
            {
                "schemaVersion": 1,
                "requestId": "case-1",
                "locale": "zh-TW",
                "rawTranscript": "現在這句",
                "protectedVocabulary": [],
                "history": ["不該送進來"],
            }
        ).encode()

        with self.assertRaisesRegex(ProtocolError, "unknown fields"):
            decode_request(io.BytesIO(body), len(body))


class PromptTests(unittest.TestCase):
    def test_prompt_is_zh_tw_and_contains_only_scoped_input(self) -> None:
        body = json.dumps(
            {
                "schemaVersion": 1,
                "requestId": "case-1",
                "locale": "zh-TW",
                "rawTranscript": "幫我看 moniit 的 PR",
                "protectedVocabulary": ["Moniit", "PR"],
            }
        ).encode()
        prompt = build_prompt(decode_request(io.BytesIO(body), len(body)))

        self.assertIn("臺灣繁體中文", prompt)
        self.assertIn("幫我看 moniit 的 PR", prompt)
        self.assertIn('"Moniit"', prompt)
        self.assertIn("完全相同的拼法", prompt)
        self.assertNotIn("conversation", prompt.lower())
        self.assertNotIn("history", prompt.lower())

    def test_extracts_json_even_when_model_wraps_it_in_a_code_fence(self) -> None:
        output = '```json\n{"refinedTranscript":"幫我看 Moniit 的 PR"}\n```'

        self.assertEqual(extract_refinement(output), "幫我看 Moniit 的 PR")

    def test_rejects_extra_model_output_fields(self) -> None:
        with self.assertRaisesRegex(ProtocolError, "model response"):
            extract_refinement(
                '{"refinedTranscript":"文字","explanation":"不應回傳"}'
            )


class HttpTests(unittest.TestCase):
    def test_invalid_content_length_is_a_redacted_client_error(self) -> None:
        with self.assertRaisesRegex(ProtocolError, "content length"):
            parse_content_length("not-a-number")


if __name__ == "__main__":
    unittest.main()
