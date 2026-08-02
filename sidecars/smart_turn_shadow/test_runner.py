import unittest

from runner import build_shadow_candidate


class SmartTurnCandidateTests(unittest.TestCase):
    def test_complete_prediction_becomes_a_shadow_timestamp(self) -> None:
        baseline = _baseline()

        result = build_shadow_candidate(
            baseline,
            lambda case_id: (True, 42),
            vad_silence_ms=200,
        )

        self.assertEqual(result["kind"], "turn")
        self.assertEqual(result["adapter"]["name"], "pipecat-smart-turn")
        self.assertEqual(result["cases"][0]["baselineSubmitAtMs"], 1800)
        self.assertEqual(result["cases"][0]["candidateSubmitAtMs"], 1242)

    def test_incomplete_prediction_is_retained_as_missing(self) -> None:
        result = build_shadow_candidate(
            _baseline(), lambda case_id: (False, 12), vad_silence_ms=200
        )

        self.assertIsNone(result["cases"][0]["candidateSubmitAtMs"])

    def test_rejects_a_non_turn_baseline(self) -> None:
        with self.assertRaisesRegex(ValueError, "turn candidate"):
            build_shadow_candidate(
                {"schemaVersion": 1, "kind": "transcript"},
                lambda case_id: (True, 1),
                vad_silence_ms=200,
            )


def _baseline():
    return {
        "schemaVersion": 1,
        "kind": "turn",
        "runId": "lulo-endpoint",
        "adapter": {"name": "lulo-rms", "version": "1"},
        "corpusId": "zh-TW-v1",
        "cases": [
            {
                "caseId": "thinking-pause",
                "speechSegments": [{"startMs": 0, "endMs": 1000}],
                "baselineSubmitAtMs": 1800,
                "candidateSubmitAtMs": None,
                "expectedSubmitWindowMs": {"start": 1200, "end": 1800},
            }
        ],
    }


if __name__ == "__main__":
    unittest.main()
