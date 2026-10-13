"""Build an agent workspace and score a finished one against hidden tests."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from pathlib import Path

from .model import REPO, ROOT, Challenge


def _sh(cmd: str, cwd: Path, timeout: float, stdin: str = "", env: dict | None = None):
    t0 = time.monotonic()
    try:
        p = subprocess.run(["bash", "-c", cmd], cwd=cwd, input=stdin, capture_output=True,
                           text=True, timeout=timeout, env=env)
        return p.returncode, p.stdout, p.stderr, time.monotonic() - t0
    except subprocess.TimeoutExpired as e:
        return 124, (e.stdout or b"").decode() if isinstance(e.stdout, bytes) else (e.stdout or ""), "timeout", time.monotonic() - t0


def norm(s: str) -> str:
    return "\n".join(line.rstrip() for line in s.rstrip().split("\n")) if s.strip() else ""


CHECK_SH = r"""#!/usr/bin/env bash
# Builds the solution and runs every example in examples/. Use this to check your work.
cd "$(dirname "$0")"
log() { printf '{"t":%s,"phase":"%s","ok":%s}\n' "$(date +%s)" "$1" "$2" >> .bench/log.jsonl; }
mkdir -p .bench
if ! ( {build} ) ; then log build false; echo "BUILD FAILED"; exit 1; fi
log build true
fail=0
for inp in examples/*.in; do
  name="${inp%.in}"
  if ! timeout 10 bash -c '{run}' < "$inp" > "$name.actual" 2> "$name.err"; then :; fi
  if diff <(sed -e 's/[[:space:]]*$//' "$name.out") <(sed -e 's/[[:space:]]*$//' "$name.actual") > "$name.diff"; then
    echo "PASS $name"
  else
    echo "FAIL $name (see $name.diff, $name.err)"; fail=1
  fi
done
log check $([ $fail = 0 ] && echo true || echo false)
exit $fail
"""


def make_workspace(ch: Challenge, lang_id: str, lang: dict, dest: Path) -> str:
    """Create dest with template, spec, examples and check.sh. Returns the agent prompt."""
    dest.mkdir(parents=True)
    shutil.copytree(ROOT / "templates" / lang_id, dest, dirs_exist_ok=True)
    for i, c in enumerate(ch.cases("examples"), 1):
        (dest / "examples").mkdir(exist_ok=True)
        (dest / "examples" / f"{i:02d}.in").write_text(c["stdin"])
        (dest / "examples" / f"{i:02d}.out").write_text(c["stdout"])
    (dest / "TASK.md").write_text(ch.spec)
    check = CHECK_SH.replace("{build}", lang["build"]).replace("{run}", lang["run"])
    (dest / "check.sh").write_text(check)
    os.chmod(dest / "check.sh", 0o755)
    for ctx in lang.get("context", []):
        if ctx == "@stdlib":
            subprocess.run(["ms", "stdlib", str(dest / "docs" / "stdlib")], check=True, capture_output=True)
        elif ctx.startswith("@repo/"):
            shutil.copytree(REPO / ctx[6:], dest / "docs", dirs_exist_ok=True)
    return (
        f"Implement the program described in TASK.md in {lang['name']}. "
        f"Edit {lang['solution']}; it reads stdin and writes stdout. "
        f"Run ./check.sh to build and test against the examples in examples/. "
        f"The final grading uses additional hidden cases of the same format, so handle the edge cases the spec describes. "
        f"{lang['notes']} Work autonomously and stop when the program is correct."
    )


def read_log(ws: Path) -> dict:
    p = ws / ".bench" / "log.jsonl"
    rows = [json.loads(l) for l in p.read_text().splitlines() if l.strip()] if p.exists() else []
    builds = [r for r in rows if r["phase"] == "build"]
    checks = [r for r in rows if r["phase"] == "check"]
    return {
        "builds": len(builds),
        "first_build_ok": bool(builds and builds[0]["ok"]),
        "checks": len(checks),
        "examples_pass": bool(checks and checks[-1]["ok"]),
    }


def grade(ch: Challenge, lang: dict, ws: Path) -> dict:
    """Build the workspace's solution and run hidden cases. Returns pass/fail details."""
    rc, _, err, _ = _sh(lang["build"], ws, 600)
    if rc != 0:
        return {"built": False, "passed": 0, "total": len(ch.cases("hidden")), "pass": False, "error": err[-500:]}
    cases = ch.cases("hidden")
    passed, failed = 0, []
    for c in cases:
        rc, out, _, _ = _sh(lang["run"], ws, ch.timeout_s, stdin=c["stdin"])
        if rc == 0 and norm(out) == norm(c["stdout"]):
            passed += 1
        else:
            failed.append(c.get("name", "?"))
    return {"built": True, "passed": passed, "total": len(cases), "pass": passed == len(cases), "failed": failed[:10]}
