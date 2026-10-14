from __future__ import annotations

import json

from .base import Harness, Usage


class Codex(Harness):
    """UNTESTED: written from the documented `codex exec --json` event stream."""
    name = "codex"

    def command(self, prompt, model, workspace):
        cmd = ["codex", "exec", "--json", "--dangerously-bypass-approvals-and-sandbox",
               "--skip-git-repo-check", "-C", str(workspace)]
        if model:
            cmd += ["-m", model]
        return cmd + [prompt]

    def parse(self, transcript):
        u = Usage()
        for line in transcript.splitlines():
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if ev.get("type") == "turn.completed":
                us = ev.get("usage", {})
                cached = us.get("cached_input_tokens", 0)
                u.tokens_in += us.get("input_tokens", 0) - cached
                u.tokens_cached += cached
                u.tokens_out += us.get("output_tokens", 0)
                u.turns += 1
        return u  # Codex reports no cost; the base class estimates it from pricing.json.
