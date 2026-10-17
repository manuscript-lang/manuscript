#!/usr/bin/env python3
"""Verifier used inside Harbor tasks: build /app, run hidden cases, write the reward.

Usage: grade.py <cases.json> <build-cmd> <run-cmd> <timeout-s>
Writes /logs/verifier/reward.txt (1 if every case passes, else 0) and detail.json.
"""
import json
import subprocess
import sys
from pathlib import Path

cases_path, build, run, timeout = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
out_dir = Path("/logs/verifier")
out_dir.mkdir(parents=True, exist_ok=True)


def norm(s):
    return "\n".join(l.rstrip() for l in s.rstrip().split("\n")) if s.strip() else ""


detail = {"built": False, "passed": 0, "total": 0, "failed": []}
log = Path("/app/.bench/log.jsonl")
rows = [json.loads(l) for l in log.read_text().splitlines() if l.strip()] if log.exists() else []
builds = [r for r in rows if r["phase"] == "build"]
detail.update(builds=len(builds), first_build_ok=bool(builds and builds[0]["ok"]), checks=sum(r["phase"] == "check" for r in rows))
cases = json.loads(Path(cases_path).read_text())
detail["total"] = len(cases)
b = subprocess.run(["bash", "-c", build], cwd="/app", capture_output=True, text=True)
if b.returncode == 0:
    detail["built"] = True
    for c in cases:
        try:
            p = subprocess.run(["bash", "-c", run], cwd="/app", input=c["stdin"], capture_output=True, text=True, timeout=timeout)
            ok = p.returncode == 0 and norm(p.stdout) == norm(c["stdout"])
        except subprocess.TimeoutExpired:
            ok = False
        if ok:
            detail["passed"] += 1
        else:
            detail["failed"].append(c.get("name", "?"))
else:
    detail["error"] = b.stderr[-500:]
(out_dir / "detail.json").write_text(json.dumps(detail))
(out_dir / "reward.txt").write_text("1" if detail["built"] and detail["passed"] == detail["total"] else "0")
