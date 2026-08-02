import json
import unittest

from run_candidate import refine_candidate


class CandidateRunnerTests(unittest.TestCase):
    def test_refines_each_case_without_changing_raw_evidence(self) -> None:
        source = {
            "schemaVersion": 1,
            "kind": "transcript",
            "runId": "whisper-run",
            "adapter": {"name": "whisper", "version": "large-v3-turbo"},
            "corpusId": "zh-TW-v1",
            "cases": [
                {
                    "caseId": "code-switch",
                    "rawTranscript": "我用 flutter",
                    "refinedTranscript": None,
                    "partialEvents": [],
                    "finalAtMs": 420,
                }
            ],
        }
        requests = []

        def propose(payload):
            requests.append(payload)
            return {
                "schemaVersion": 1,
                "requestId": payload["requestId"],
                "refinedTranscript": "我用 Flutter",
                "providerId": "qwen",
                "providerVersion": "1",
            }

        result = refine_candidate(source, ["Flutter"], propose)

        self.assertEqual(result["runId"], "whisper-run-qwen-shadow")
        self.assertEqual(result["adapter"], {"name": "qwen", "version": "1"})
        self.assertEqual(result["cases"][0]["rawTranscript"], "我用 flutter")
        self.assertEqual(result["cases"][0]["refinedTranscript"], "我用 Flutter")
        self.assertEqual(requests[0]["protectedVocabulary"], ["Flutter"])
        self.assertNotIn("history", requests[0])

    def test_rejects_non_transcript_candidates(self) -> None:
        with self.assertRaisesRegex(ValueError, "transcript candidate"):
            refine_candidate(
                {"schemaVersion": 1, "kind": "turn", "cases": []}, [], lambda _: {}
            )


if __name__ == "__main__":
    unittest.main()
