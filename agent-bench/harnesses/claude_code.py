from __future__ import annotations

import json

from .base import Harness, Usage


class ClaudeCode(Harness):
    name = "claude_code"

    def command(self, prompt, model, workspace):
        cmd = ["claude", "-p", prompt, "--output-format", "stream-json", "--verbose",
               "--dangerously-skip-permissions", "--no-session-persistence"]
        if model:
            cmd += ["--model", model]
        return cmd

    def parse(self, transcript):
        for line in reversed(transcript.splitlines()):
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if ev.get("type") == "result":
                u = ev.get("usage", {})
                return Usage(
                    tokens_in=u.get("input_tokens", 0),
                    tokens_cached=u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0),
                    tokens_out=u.get("output_tokens", 0),
                    turns=ev.get("num_turns", 0),
                    cost_usd=ev.get("total_cost_usd", 0.0),
                    cost_source="harness",
                )
        return Usage()
