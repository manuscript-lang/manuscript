#!/usr/bin/env python3
"""Agent-effectiveness benchmark runner. See README.md."""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import tempfile
import time
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from core.model import ROOT, load_challenges, load_languages  # noqa: E402
from core.workspace import grade, make_workspace, read_log  # noqa: E402
from harnesses import HARNESSES  # noqa: E402

RESULTS = ROOT / "results"


def run_one(ch, lang_id, lang, harness, model, timeout_s, keep, out_file, tag):
    run_id = uuid.uuid4().hex[:10]
    base = Path(tempfile.mkdtemp(prefix="ms-bench-"))
    ws = base / "ws"
    prompt = make_workspace(ch, lang_id, lang, ws)
    transcripts = RESULTS / "transcripts"
    transcripts.mkdir(parents=True, exist_ok=True)
    if harness.name == "oracle":
        src = ch.solution(lang_id)
        dst = ws / lang["solution"]
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(next(src.iterdir()), dst)
        agent = {"usage": harness.parse("").dict(), "wall_s": 0.0, "exit_code": 0, "timed_out": False}
    else:
        agent = harness.run(prompt, model, ws, timeout_s, transcripts / f"{run_id}.log")
    log = read_log(ws)
    # Cheap leak guard: flag runs whose transcript mentions the benchmark's own challenge tree.
    tpath = transcripts / f"{run_id}.log"
    peeked = tpath.exists() and any(m in tpath.read_text(errors="replace") for m in ("ms-bench/challenges", "hidden/cases.json"))
    g = grade(ch, lang, ws)
    rec = {
        "run_id": run_id, "ts": int(time.time()), "tag": tag,
        "challenge": ch.id, "category": ch.category, "tier": ch.tier,
        "language": lang_id, "harness": harness.name, "model": model,
        **agent, **log, "suspect_peek": peeked, "grade": g, "pass": g["pass"],
    }
    with out_file.open("a") as f:
        f.write(json.dumps(rec) + "\n")
    if keep:
        print(f"  workspace kept: {ws}")
    else:
        shutil.rmtree(base, ignore_errors=True)
    return rec


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list", help="list challenges and languages")
    r = sub.add_parser("run", help="run agents on challenges")
    r.add_argument("--harness", required=True, choices=sorted(HARNESSES))
    r.add_argument("--model")
    r.add_argument("--challenges", default="", help="comma list of ids or prefixes (default all)")
    r.add_argument("--languages", default="", help="comma list (default all)")
    r.add_argument("--repeat", type=int, default=1)
    r.add_argument("--timeout", type=int, default=900, help="agent wall-clock limit, seconds")
    r.add_argument("--keep", action="store_true", help="keep workspaces")
    r.add_argument("--tag", default="", help="free-form label stored with each run")
    r.add_argument("--out", default=str(RESULTS / "runs.jsonl"))
    o = sub.add_parser("oracle", help="run reference solutions through the grader (validates tests)")
    o.add_argument("--challenges", default="")
    o.add_argument("--languages", default="")
    a = ap.parse_args()

    if a.cmd == "list":
        for c in load_challenges():
            print(f"{c.id:28} {c.category:14} tier {c.tier}")
        print("languages:", ", ".join(load_languages()))
        print("harnesses:", ", ".join(sorted(HARNESSES)))
        return 0

    split = lambda s: [x for x in s.split(",") if x]  # noqa: E731
    chs = load_challenges(split(a.challenges))
    langs = load_languages(split(a.languages))
    if a.cmd == "oracle":
        out = RESULTS / "oracle.jsonl"
        out.unlink(missing_ok=True)
        harness, model, repeat, timeout, keep, tag = HARNESSES["oracle"], None, 1, 0, False, "oracle"
    else:
        out, harness, model, repeat, timeout, keep, tag = Path(a.out), HARNESSES[a.harness], a.model, a.repeat, a.timeout, a.keep, a.tag
    bad = 0
    for ch in chs:
        for lid, lang in langs.items():
            for _ in range(repeat):
                rec = run_one(ch, lid, lang, harness, model, timeout, keep, out, tag)
                g = rec["grade"]
                print(f"{'PASS' if rec['pass'] else 'FAIL'} {ch.id} {lid} {g['passed']}/{g['total']} "
                      f"turns={rec['usage']['turns']} cost=${rec['usage']['cost_usd']:.3f} {rec['wall_s']}s")
                bad += not rec["pass"]
    if a.cmd == "oracle":
        out.unlink(missing_ok=True)  # oracle output is a check, not data
    return 1 if (bad and a.cmd == "oracle") else 0


if __name__ == "__main__":
    sys.exit(main())
