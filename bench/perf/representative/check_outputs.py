"""Check ordinary reference cases, optimized MIR and native artifact equality."""
import argparse
import hashlib
import json
import os
import pathlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--inputs", type=pathlib.Path, required=True)
parser.add_argument("--output", type=pathlib.Path, required=True)
parser.add_argument("--before", type=pathlib.Path, required=True)
parser.add_argument("--after", type=pathlib.Path, required=True)
args = parser.parse_args()
root = args.output.resolve()
env = os.environ | {"MS_EMIT_OPT": "1", "XDG_CACHE_HOME": str(root / "cache")}
report = []
for folder in sorted(args.inputs.resolve().iterdir()):
    if not folder.is_dir():
        continue
    name = folder.name
    mir = []
    binaries = []
    for label, compiler in [("before", args.before), ("after", args.after)]:
        data = subprocess.check_output([str(compiler.resolve()), "emit", str(folder / "main.ms")], env=env)
        (root / f"{label}-{name}.mir").write_bytes(data)
        mir.append(data)
        binaries.append((root / f"{label}-{name}").read_bytes())
    assert mir[0] == mir[1], (name, "optimized MIR differs")
    assert binaries[0] == binaries[1], (name, "native executable differs")
    casefile = folder / "cases.json"
    cases = json.loads(casefile.read_text()) if casefile.exists() else []
    passed = 0
    for label in ["before", "after", "rust"]:
        binary = root / f"{label}-{name}"
        if not binary.exists():
            continue
        for case in cases:
            p = subprocess.run([str(binary)], input=case["stdin"].encode(), capture_output=True, check=True)
            assert p.stdout == case["stdout"].encode(), (label, name, case["name"], p.stdout, p.stderr)
            passed += 1
    report.append(dict(case=name, optimized_mir_sha256=hashlib.sha256(mir[0]).hexdigest(),
                       native_sha256=hashlib.sha256(binaries[0]).hexdigest(),
                       native_bytes=len(binaries[0]), checked_reference_cases=passed))
assert report, "no workloads"
print(json.dumps(report, indent=2))
