from __future__ import annotations

import json

from .base import Harness, Usage


class Pi(Harness):
    """UNTESTED: pi's JSON event schema is assumed; sums `usage` blocks on assistant messages."""
    name = "pi"

    def command(self, prompt, model, workspace):
        cmd = ["pi", "--mode", "json", "-p", prompt]
        if model:
            cmd += ["--model", model]
        return cmd

    def parse(self, transcript):
        u = Usage()
        for line in transcript.splitlines():
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            msg = ev.get("message") or {}
            us = msg.get("usage")
            if ev.get("type") == "message_end" and msg.get("role") == "assistant" and us:
                u.tokens_in += us.get("input", 0)
                u.tokens_cached += us.get("cacheRead", 0) + us.get("cacheWrite", 0)
                u.tokens_out += us.get("output", 0)
                u.turns += 1
                c = (us.get("cost") or {}).get("total")
                if c is not None:
                    u.cost_usd += c
                    u.cost_source = "harness"
        return u
