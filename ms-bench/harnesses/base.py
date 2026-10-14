"""Harness adapter interface.

A harness drives one coding agent CLI inside a workspace. To add one, subclass
Harness, implement `command` and `parse`, and register it in harnesses/__init__.py.
"""
from __future__ import annotations

import subprocess
import time
from abc import ABC, abstractmethod
from dataclasses import asdict, dataclass
from pathlib import Path

from core.model import cost_from_tokens


@dataclass
class Usage:
    tokens_in: int = 0        # uncached input tokens
    tokens_cached: int = 0    # cache reads (and writes, where the harness reports them together)
    tokens_out: int = 0
    turns: int = 0
    cost_usd: float = 0.0
    cost_source: str = "none"  # "harness" | "estimated" | "none"

    def dict(self):
        return asdict(self)


class Harness(ABC):
    name: str

    @abstractmethod
    def command(self, prompt: str, model: str | None, workspace: Path) -> list[str]:
        """argv that runs the agent non-interactively in `workspace` and exits when done."""

    @abstractmethod
    def parse(self, transcript: str) -> Usage:
        """Extract usage from the harness's raw stdout."""

    def run(self, prompt: str, model: str | None, workspace: Path, timeout_s: int, transcript: Path) -> dict:
        t0 = time.monotonic()
        timed_out = False
        try:
            p = subprocess.run(self.command(prompt, model, workspace), cwd=workspace, capture_output=True,
                               text=True, timeout=timeout_s, stdin=subprocess.DEVNULL)
            out, rc = p.stdout, p.returncode
        except subprocess.TimeoutExpired as e:
            out = e.stdout.decode() if isinstance(e.stdout, bytes) else (e.stdout or "")
            rc, timed_out = 124, True
        wall = time.monotonic() - t0
        transcript.write_text(out)
        u = self.parse(out)
        if u.cost_source == "none" and (u.tokens_in or u.tokens_out):
            u.cost_usd = cost_from_tokens(u.tokens_in, u.tokens_cached, u.tokens_out, model or "default")
            u.cost_source = "estimated"
        return {"usage": u.dict(), "wall_s": round(wall, 2), "exit_code": rc, "timed_out": timed_out}
