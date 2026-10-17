#!/usr/bin/env python3
"""Export agent-bench challenges as Harbor tasks (one per challenge x language).

    python3 agent-bench/export_harbor.py --out /tmp/agent-bench-tasks [--challenges c01,c02] [--languages ms,go]
        [--ms-binary ./ms]

Each task directory: instruction.md, task.toml, environment/{Dockerfile,workspace/,ms}, tests/{test.sh,grade.py,cases.json},
solution/solve.sh. Hidden cases live only in tests/, which Harbor uploads at verification time.
The output is generated; do not commit it.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from core.model import ROOT, load_challenges, load_languages  # noqa: E402
from core.workspace import make_workspace  # noqa: E402

BASE_IMAGES = {
    "ts": "node:22-bookworm",
    "go": "golang:1.25-bookworm",
    "rust": "rust:1-bookworm",
    "ms": "ubuntu:24.04",
}

DOCKERFILE = """FROM {base}
RUN {install}
{extra}WORKDIR /app
COPY workspace /app
"""


def dockerfile(lang_id: str) -> str:
    install = "apt-get update && apt-get install -y --no-install-recommends python3 ca-certificates curl git && rm -rf /var/lib/apt/lists/*"
    extra = ""
    if lang_id.startswith("ms"):
        extra = "COPY ms /usr/local/bin/ms\n"
    return DOCKERFILE.format(base=BASE_IMAGES[lang_id], install=install, extra=extra)


def task_toml(name: str, ch, agent_timeout: int) -> str:
    return f"""schema_version = "1.4"
artifacts = []

[task]
name = "agent-bench/{name}"
version = "1.0.0"
description = "{ch.title} ({ch.category}, tier {ch.tier})"
authors = []
keywords = ["agent-bench", "{ch.category}"]

[metadata]
category = "{ch.category}"
tier = {ch.tier}

[verifier]
timeout_sec = 600.0
collect = []

[verifier.env]

[agent]
timeout_sec = {float(agent_timeout)}

[environment]
network_mode = "public"
build_timeout_sec = 900.0
os = "linux"
mcp_servers = []

[environment.env]

[solution.env]
"""


def export_one(ch, lang_id, lang, out: Path, ms_binary: Path | None, agent_timeout: int):
    name = f"{ch.id}-{lang_id}"
    d = out / name
    if d.exists():
        shutil.rmtree(d)
    (d / "environment").mkdir(parents=True)
    prompt = make_workspace(ch, lang_id, lang, d / "environment" / "workspace")
    (d / "instruction.md").write_text(prompt + "\n\n---\n\n" + ch.spec)
    (d / "task.toml").write_text(task_toml(name, ch, agent_timeout))
    (d / "environment" / "Dockerfile").write_text(dockerfile(lang_id))
    if lang_id.startswith("ms"):
        if ms_binary is None:
            print(f"  note: {name} needs --ms-binary for its Docker image (local-process env uses PATH)", file=sys.stderr)
        else:
            shutil.copy2(ms_binary, d / "environment" / "ms")
    tests = d / "tests"
    tests.mkdir()
    shutil.copy(ROOT / "harbor" / "grade.py", tests / "grade.py")
    (tests / "cases.json").write_text(json.dumps(ch.cases("hidden")))
    (tests / "test.sh").write_text(
        "#!/bin/bash\n"
        f"python3 /tests/grade.py /tests/cases.json {json.dumps(lang['build'])} {json.dumps(lang['run'])} {ch.timeout_s}\n"
    )
    sol = ch.solution(lang.get("template", lang_id)) / (Path(lang["solution"]).name + ".ref")
    (d / "solution").mkdir()
    if sol.exists():
        shutil.copy(sol, d / "solution" / "reference")
        (d / "solution" / "solve.sh").write_text(
            "#!/bin/bash\n"
            f"mkdir -p \"$(dirname /app/{lang['solution']})\"\n"
            f"cp \"$(dirname \"$0\")/reference\" /app/{lang['solution']}\n"
        )
    else:  # large challenges are oracle-validated in Go only; the oracle agent has nothing to apply
        (d / "solution" / "solve.sh").write_text("#!/bin/bash\necho 'no reference solution for this language' >&2\nexit 1\n")
    for f in (tests / "test.sh", d / "solution" / "solve.sh"):
        f.chmod(0o755)
    return d


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True)
    ap.add_argument("--challenges", default="")
    ap.add_argument("--languages", default="")
    ap.add_argument("--ms-binary", type=Path)
    ap.add_argument("--agent-timeout", type=int, default=900)
    a = ap.parse_args()
    split = lambda s: [x for x in s.split(",") if x]  # noqa: E731
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    n = 0
    for ch in load_challenges(split(a.challenges)):
        for lid, lang in load_languages(split(a.languages)).items():
            export_one(ch, lid, lang, out, a.ms_binary, a.agent_timeout)
            n += 1
    print(f"exported {n} tasks to {out}")


if __name__ == "__main__":
    main()
