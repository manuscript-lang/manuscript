from __future__ import annotations

from .base import Harness, Usage


class Oracle(Harness):
    """Not an agent: run.py copies the reference solution in. Used to validate challenges and tests."""
    name = "oracle"

    def command(self, prompt, model, workspace):
        return ["true"]

    def parse(self, transcript):
        return Usage()
