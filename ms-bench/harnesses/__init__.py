from .claude_code import ClaudeCode
from .codex import Codex
from .oracle import Oracle
from .pi import Pi

HARNESSES = {h.name: h for h in (ClaudeCode(), Codex(), Pi(), Oracle())}
