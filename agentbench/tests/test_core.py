import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from core.model import cost_from_tokens, load_challenges, load_languages  # noqa: E402
from core.workspace import norm  # noqa: E402
from harnesses.claude_code import ClaudeCode  # noqa: E402
from harnesses.codex import Codex  # noqa: E402


class CoreTests(unittest.TestCase):
    def test_norm_ignores_trailing_whitespace_only(self):
        self.assertEqual(norm("a  \nb\n\n"), norm("a\nb"))
        self.assertNotEqual(norm("a\nb"), norm("b\na"))
        self.assertEqual(norm(""), norm("\n"))

    def test_every_challenge_is_complete(self):
        langs = load_languages()
        chs = load_challenges()
        self.assertTrue(chs)
        for ch in chs:
            self.assertTrue(ch.cases("examples"), ch.id)
            self.assertGreater(len(ch.cases("hidden")), len(ch.cases("examples")) - 1, ch.id)
            visible = {c["stdin"] for c in ch.cases("examples")}
            self.assertTrue(any(c["stdin"] not in visible for c in ch.cases("hidden")), f"{ch.id}: hidden cases add nothing")
            for lid, lang in langs.items():
                sol = ch.solution(lid) / (Path(lang["solution"]).name + ".ref")
                self.assertTrue(sol.is_file(), f"{ch.id}: missing {lid} reference solution")

    def test_claude_code_parse(self):
        out = "\n".join(json.dumps(e) for e in [
            {"type": "assistant"},
            {"type": "result", "num_turns": 7, "total_cost_usd": 0.5,
             "usage": {"input_tokens": 10, "output_tokens": 20, "cache_read_input_tokens": 100, "cache_creation_input_tokens": 5}},
        ])
        u = ClaudeCode().parse(out)
        self.assertEqual((u.tokens_in, u.tokens_cached, u.tokens_out, u.turns, u.cost_usd, u.cost_source),
                         (10, 105, 20, 7, 0.5, "harness"))

    def test_codex_parse_sums_turns_and_splits_cache(self):
        ev = {"type": "turn.completed", "usage": {"input_tokens": 100, "cached_input_tokens": 60, "output_tokens": 5}}
        u = Codex().parse("\n".join([json.dumps(ev)] * 2))
        self.assertEqual((u.tokens_in, u.tokens_cached, u.tokens_out, u.turns), (80, 120, 10, 2))

    def test_cost_estimate(self):
        self.assertAlmostEqual(cost_from_tokens(1_000_000, 0, 0), 3.0)


if __name__ == "__main__":
    unittest.main()
