"""Linux wait4 measurements, full-output validation, and balanced before/after trials."""
import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument("--inputs", type=pathlib.Path, required=True)
parser.add_argument("--output", type=pathlib.Path, required=True)
parser.add_argument("--ms", action="append", required=True, help="label=/absolute/path/to/ms")
parser.add_argument("--stages", action="append", default=[], help="label=/absolute/path/to/perf_stages")
parser.add_argument("--repeats", type=int, default=7)
parser.add_argument("--phase", choices=["build", "runtime", "tooling", "stages", "cold", "memory", "memory-build"], required=True)
parser.add_argument("--rss", type=pathlib.Path, help="compiled rss.c helper (required for memory phases)")
parser.add_argument("--cases", default="hello,c03-csv-group-sum,c13-inventory-orders,c25-log-analyzer,rules-100,rules-200,rules-400")
args = parser.parse_args()
assert args.repeats > 0, "at least one measured trial is required"
if args.phase.startswith("memory"):
    assert args.rss is not None, "memory measurements require the isolated RSS helper"
inputs, out = args.inputs.resolve(), args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
versions = dict(item.split("=", 1) for item in args.ms)
assert len(versions) == len(args.ms), "compiler labels must be unique"
stages = dict(item.split("=", 1) for item in args.stages)
cases = args.cases.split(",")
env = os.environ.copy()
for key in ["MS_BACKEND", "MS_LLVM_TOOLS", "MS_KEEP_LL", "MS_RT_LIB", "MS_EMIT_OPT"]:
    env.pop(key, None)
env["XDG_CACHE_HOME"] = str(out / "cache")
env["MANUSCRIPT_CACHE_DIR"] = str(out / "run-cache")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def measure(command, label, name, phase, trial, stdin=None, expected=None, extra=None):
    stem = out / f"{phase}-{label}-{name}-{trial}"
    sample_env = env | (extra or {})
    with open(stdin or os.devnull, "rb") as source, open(str(stem)+".stdout", "wb") as stdout, open(str(stem)+".stderr", "wb") as stderr:
        started = time.perf_counter()
        measured_command = command
        if args.rss is not None:
            measured_command = [str(args.rss.resolve()), str(stem)+".rss.json", *command]
        child = subprocess.Popen(measured_command, stdin=source, stdout=stdout, stderr=stderr,
                                 env=sample_env, cwd=ROOT)
        _, status, usage = os.wait4(child.pid, 0)
        elapsed = time.perf_counter() - started
        child.returncode = os.waitstatus_to_exitcode(status)
    data = pathlib.Path(str(stem)+".stdout").read_bytes()
    error = pathlib.Path(str(stem)+".stderr").read_text()
    record = dict(label=label, case=name, phase=phase, trial=trial, command=list(map(str, command)),
                  wall_s=elapsed, user_s=usage.ru_utime, system_s=usage.ru_stime,
                  maxrss_kib=usage.ru_maxrss, exit=child.returncode,
                  stdout_sha256=digest(data), stdout_bytes=len(data))
    record["isolated_rss"] = args.rss is not None
    if args.rss is not None:
        record["launcher_tree_maxrss_kib"] = record["maxrss_kib"]
        record["maxrss_kib"] = json.loads(pathlib.Path(str(stem)+".rss.json").read_text())["maxrss_kib"]
    if expected is not None:
        record["correct"] = data == expected
    if phase == "stages":
        record["stages"] = [json.loads(line) for line in error.splitlines() if line.startswith('{"stage":')]
        metrics = pathlib.Path(sample_env["LLVM_METRICS"])
        record["llvm"] = [json.loads(line) for line in metrics.read_text().splitlines()]
        assert [r["tool"] for r in record["llvm"]] == ["opt", "llc"], record
    with open(out / f"{args.phase}.jsonl", "a") as log:
        log.write(json.dumps(record) + "\n")
    assert child.returncode == 0, (command, error)
    assert expected is None or data == expected, (command, "output mismatch", data[:300])
    return data


labels = list(versions)
for trial in range(-1, args.repeats):
    # Trial -1 warms process file pages and validates before timing. Cold runs each get a fresh cache.
    for name in (cases if trial % 2 == 0 else list(reversed(cases))):
        for label in (labels if trial % 2 == 0 else list(reversed(labels))):
            folder = inputs / name
            binary = out / f"{label}-{name}"
            expected = (folder / "expected").read_bytes()
            if args.phase in ("build", "cold", "memory-build"):
                extra = None
                if args.phase == "cold":
                    extra = {"XDG_CACHE_HOME": str(out / f"cold-{label}-{name}-{trial}")}
                measure([versions[label], "build", str(folder / "main.ms"), "--build-type", "Release", "-o", str(binary)],
                        label, name, args.phase, trial, extra=extra)
                # Validation runs separately and is not included in build wall time or build RSS.
                measure([str(binary)], label, name, "validate", trial, folder / "stdin", expected)
            elif args.phase in ("runtime", "memory"):
                measure([str(binary)], label, name, args.phase, trial, folder / "stdin", expected)
            elif args.phase == "tooling":
                for command in ["check", "inspect", "diagram"]:
                    cmd = [versions[label], command, str(folder / "main.ms")]
                    if command == "check":
                        cmd.append("--json")
                    data = measure(cmd, label, name, command, trial)
                    oracle = out / f"tool-{name}-{command}.expected"
                    if not oracle.exists():
                        oracle.write_bytes(data)
                    assert data == oracle.read_bytes(), (cmd, "tool output differs")
            else:
                tools = out / "llvm-wrappers"
                tools.mkdir(exist_ok=True)
                wrapper = ROOT / "bench/perf/representative/llvm_wrapper.py"
                wrapper.chmod(0o755)
                for tool in ["opt", "llc"]:
                    path = tools / tool
                    if not path.exists():
                        path.symlink_to(wrapper)
                metrics = out / f"llvm-{label}-{name}-{trial}.jsonl"
                assert not metrics.exists(), metrics
                extra = dict(MS_LLVM_TOOLS=str(tools), REAL_LLVM_TOOLS=str(ROOT / "target/llvm-bundle/install/bin"), LLVM_METRICS=str(metrics))
                measure([stages[label], str(folder / "main.ms"), str(binary)+"-staged", str(ROOT / "target/ms-native/libms_native.a")],
                        label, name, "stages", trial, extra=extra)
                measure([str(binary)+"-staged"], label, name, "validate-stages", trial, folder / "stdin", expected)
            print(f"{args.phase} {trial} {label} {name}", flush=True)
