#!/usr/bin/env python3
"""Collect Harbor trials into results/trials.jsonl and render results/leaderboard.md.

    python3 agent-bench/leaderboard.py collect JOBS_DIR [JOBS_DIR ...]   # append/replace trials by trial id
    python3 agent-bench/leaderboard.py render                          # write results/leaderboard.md

Pass rate counts every trial. Cost, tokens, turns and time average over PASSING trials only, so a cheap wrong
answer never improves a ranking. Tokens are input (cache reads included) plus output. Turns are agent steps in
the Harbor trajectory. Ranking: pass rate, then mean cost of passing trials.
"""
from __future__ import annotations

import json
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from statistics import mean, pstdev

ROOT = Path(__file__).resolve().parent
TRIALS = ROOT / "results" / "trials.jsonl"
BOARD = ROOT / "results" / "leaderboard.md"
LANG_NAMES = {"ts": "TypeScript", "go": "Go", "rust": "Rust", "ms": "Manuscript"}
MIN_RUNS = 3  # cells with fewer trials are marked provisional


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


CATEGORIES = ("base", "docs", "reads", "build", "writes", "model output")


def categorize(step) -> str:
    """Which kind of content a step's tool results add to the context."""
    calls = step.get("tool_calls") or []
    text = " ".join(json.dumps(c.get("arguments", {})) for c in calls)
    names = {c.get("function_name") for c in calls}
    if names & {"Write", "Edit", "MultiEdit", "NotebookEdit"}:
        return "writes"
    if "docs" in text:
        return "docs"
    if any(k in text for k in ("check.sh", "ms build", "ms check", "ms run", "cargo ", "go build", "node ")):
        return "build"
    return "reads"


def breakdown(steps) -> dict[str, float]:
    """Attribute input tokens (cache reads included) to the source of the context they carry.

    Each step re-sends the whole context. We track how the context grew since the previous step, credit the growth to
    the previous step's tool category (and its completion tokens to "model output"), and split every step's prompt
    tokens by the running composition. The total equals the sum of prompt tokens over agent steps.
    """
    comp = {c: 0.0 for c in CATEGORIES}
    out = {c: 0.0 for c in CATEGORIES}
    prev_prompt, prev_step = 0, None
    for st in steps:
        m = st.get("metrics")
        if st.get("source") != "agent" or not m:
            continue
        prompt = m.get("prompt_tokens") or 0
        if prev_step is None:
            comp["base"] = prompt
        else:
            pm = prev_step["metrics"]
            comp["model output"] += pm.get("completion_tokens") or 0
            comp[categorize(prev_step)] += max(0, prompt - prev_prompt - (pm.get("completion_tokens") or 0))
        total = sum(comp.values()) or 1
        for c in CATEGORIES:
            out[c] += prompt * comp[c] / total
        prev_prompt, prev_step = prompt, st
    return out


def read_trial(d: Path) -> dict | None:
    f = d / "result.json"
    if not f.is_file():
        return None
    r = json.loads(f.read_text())
    if "task_name" not in r:  # a job-level result, not a trial
        return None
    name = r["task_name"].split("/")[-1]
    cid, lang = name.rsplit("-", 1)
    mf = ROOT / "challenges" / cid / "challenge.json"
    if not mf.is_file():  # challenge was renamed or removed since the trial ran
        return None
    meta = json.loads(mf.read_text())
    ar = r.get("agent_result") or {}
    reward = ((r.get("verifier_result") or {}).get("rewards") or {}).get("reward")
    detail = {}
    if (d / "verifier" / "detail.json").is_file():
        detail = json.loads((d / "verifier" / "detail.json").read_text())
    turns, src = 0, {}
    if (d / "agent" / "trajectory.json").is_file():
        steps = json.loads((d / "agent" / "trajectory.json").read_text()).get("steps", [])
        turns = sum(1 for s in steps if s.get("source") == "agent")
        src = {k: round(v) for k, v in breakdown(steps).items()}
    ex = r.get("agent_execution") or {}
    wall = ts(ex["finished_at"]) - ts(ex["started_at"]) if ex.get("started_at") and ex.get("finished_at") else 0.0
    return {
        "trial": r["trial_name"], "challenge": cid, "category": meta["category"], "tier": meta["tier"], "language": lang,
        "agent": r["config"]["agent"].get("name"), "model": r["config"]["agent"].get("model_name"),
        "pass": reward == 1.0, "errored": bool(r.get("exception_info")) or reward is None,
        "cases_passed": detail.get("passed"), "cases_total": detail.get("total"),
        "first_build_ok": detail.get("first_build_ok"), "builds": detail.get("builds"),
        "tokens_in": ar.get("n_input_tokens") or 0, "tokens_cached": ar.get("n_cache_tokens") or 0,
        "tokens_out": ar.get("n_output_tokens") or 0, "cost_usd": ar.get("cost_usd") or 0.0,
        "turns": turns, "wall_s": round(wall, 1), "input_by_source": src, "started": r.get("started_at") or "",
    }


def collect(dirs):
    rows = {}
    if TRIALS.is_file():
        for l in TRIALS.read_text().splitlines():
            t = json.loads(l)
            rows[t["trial"]] = t
    for jobs in dirs:
        for d in Path(jobs).glob("**/*__*"):
            if d.is_dir() and (d / "result.json").is_file() and d.name.count("__") == 1:
                t = read_trial(d)
                if t:
                    rows[t["trial"]] = t
    latest = {}  # a resumed job reruns trials; keep one (the latest) per challenge, language, agent and model
    for t in sorted(rows.values(), key=lambda t: t.get("started", "")):
        latest[(t["challenge"], t["language"], t["agent"], t["model"])] = t
    rows = {t["trial"]: t for t in latest.values()}
    TRIALS.parent.mkdir(exist_ok=True)
    TRIALS.write_text("".join(json.dumps(t) + "\n" for t in sorted(rows.values(), key=lambda t: t["trial"])))
    print(f"{len(rows)} trials in {TRIALS}")


def agg(rs):
    ok = [r for r in rs if r["pass"]]
    m = lambda f: mean(f(r) for r in ok) if ok else None  # noqa: E731
    return {
        "n": len(rs), "pass": len(ok) / len(rs),
        "fb": mean(1 if r["first_build_ok"] else 0 for r in rs),
        "tokens": m(lambda r: r["tokens_in"] + r["tokens_out"]), "turns": m(lambda r: r["turns"]),
        "wall": m(lambda r: r["wall_s"]), "cost": m(lambda r: r["cost_usd"]),
    }


def fmt(v, kind):
    if v is None:
        return "-"
    return {"pct": f"{v:.0%}", "tok": f"{v/1000:.0f}k", "n": f"{v:.1f}", "usd": f"${v:.3f}"}[kind]


def table(title, groups, label):
    lines = [f"### {title}", "", f"| rank | {label} | trials | pass | first build ok | tokens | turns | wall s | cost |",
             "|---:|---|---:|---:|---:|---:|---:|---:|---:|"]
    rows = sorted(((k, agg(v)) for k, v in groups.items()), key=lambda kv: (-kv[1]["pass"], kv[1]["cost"] if kv[1]["cost"] is not None else 1e9))
    for i, (k, a) in enumerate(rows, 1):
        prov = " (provisional)" if a["n"] < MIN_RUNS * 5 else ""
        lines.append(f"| {i} | {k}{prov} | {a['n']} | {fmt(a['pass'],'pct')} | {fmt(a['fb'],'pct')} | {fmt(a['tokens'],'tok')} | "
                     f"{fmt(a['turns'],'n')} | {fmt(a['wall'],'n')} | {fmt(a['cost'],'usd')} |")
    return "\n".join(lines) + "\n"


def source_table(rows):
    """Where input tokens go, per language, averaged over passing trials."""
    lines = ["### Where the input tokens go (passing trials, mean per trial)", "",
             "Input tokens include cache reads. `base` is the system prompt plus the task, re-sent on every step, so it scales with turns; `docs` is the Manuscript docs bundle when the agent reads it;",
             "`reads` is other file and command output; `build` is check/build/run output (compile-error retries); `writes` is edited code echoed back; `model output` is the agent's own text and tool calls.", "",
             "| language | input | output | " + " | ".join(CATEGORIES) + " |", "|---|---:|---:|" + "---:|" * len(CATEGORIES)]
    for lang in ("ts", "go", "rust", "ms"):
        ok = [t for t in rows if t["language"] == lang and t["pass"] and t.get("input_by_source")]
        if not ok:
            continue
        mean_in = mean(t["tokens_in"] for t in ok)
        cells = [f"{mean(t['input_by_source'][c] for t in ok)/1000:.0f}k" for c in CATEGORIES]
        lines.append(f"| {LANG_NAMES[lang]} | {mean_in/1000:.0f}k | {mean(t['tokens_out'] for t in ok)/1000:.1f}k | " + " | ".join(cells) + " |")
    return "\n".join(lines) + "\n"


def render():
    trials = [json.loads(l) for l in TRIALS.read_text().splitlines() if l.strip()]
    clean = [t for t in trials if not t["errored"]]
    out = ["# agent-bench leaderboard", "",
           f"{len(trials)} trials ({len(trials) - len(clean)} errored and excluded). Pass rate counts all scored trials; tokens, turns, wall time and cost average over passing trials only. Ranked by pass rate, then cost.", ""]
    by = lambda keyf, rows=clean: _group(rows, keyf)  # noqa: E731
    out.append(table("Languages (all models)", by(lambda t: LANG_NAMES.get(t["language"], t["language"])), "language"))
    out.append(table("Models (all languages)", by(lambda t: f"{t['agent']} / {t['model']}"), "agent / model"))
    out.append(table("Model x language", by(lambda t: f"{t['model']} / {LANG_NAMES.get(t['language'], t['language'])}"), "model / language"))
    out.append(source_table(clean))
    for cat in sorted({t["category"] for t in clean}):
        rows = [t for t in clean if t["category"] == cat]
        out.append(table(f"Category: {cat}", _group(rows, lambda t: LANG_NAMES.get(t["language"], t["language"])), "language"))
    for tier in sorted({t["tier"] for t in clean}):
        rows = [t for t in clean if t["tier"] == tier]
        out.append(table(f"Tier {tier}", _group(rows, lambda t: LANG_NAMES.get(t["language"], t["language"])), "language"))
    BOARD.write_text("\n".join(out))
    print(f"wrote {BOARD}")


def _group(rows, keyf):
    g = defaultdict(list)
    for t in rows:
        g[keyf(t)].append(t)
    return g


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "collect":
        collect(sys.argv[2:])
    elif len(sys.argv) == 2 and sys.argv[1] == "render":
        render()
    else:
        sys.exit(__doc__)
