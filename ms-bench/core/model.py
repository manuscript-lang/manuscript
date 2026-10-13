"""Data loading shared by the runner: challenges, languages, pricing."""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT.parent


@dataclass
class Challenge:
    id: str
    title: str
    category: str
    tier: int
    timeout_s: int
    dir: Path

    @property
    def spec(self) -> str:
        return (self.dir / "spec.md").read_text()

    def cases(self, which: str) -> list[dict]:
        """which is 'examples' (visible to the agent) or 'hidden'."""
        return json.loads((self.dir / which / "cases.json").read_text())

    def solution(self, lang: str) -> Path:
        return self.dir / "solutions" / lang


def load_challenges(ids: list[str] | None = None) -> list[Challenge]:
    out = []
    for d in sorted((ROOT / "challenges").iterdir()):
        meta = d / "challenge.json"
        if not meta.is_file():
            continue
        m = json.loads(meta.read_text())
        if ids and not any(d.name == i or d.name.startswith(i + "-") for i in ids):
            continue
        out.append(Challenge(d.name, m["title"], m["category"], m["tier"], m.get("timeout_s", 5), d))
    return out


def load_languages(ids: list[str] | None = None) -> dict[str, dict]:
    langs = json.loads((ROOT / "languages.json").read_text())
    if ids:
        unknown = set(ids) - set(langs)
        if unknown:
            raise SystemExit(f"unknown languages: {sorted(unknown)}")
        langs = {k: v for k, v in langs.items() if k in ids}
    return langs


def cost_from_tokens(tokens_in: int, cached: int, tokens_out: int, model: str = "default") -> float:
    """Estimate USD from pricing.json. tokens_in excludes cached tokens."""
    table = json.loads((ROOT / "pricing.json").read_text())
    p = table.get(model, table["default"])
    return (tokens_in * p["input"] + cached * p["cached_input"] + tokens_out * p["output"]) / 1e6
