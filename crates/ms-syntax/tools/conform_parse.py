"""Replays the conformance corpus's parse-phase fixtures (tests/conformance) through ms-syntax:
parse diagnostics and `ms fmt` output must equal what the Go oracle recorded."""
import glob, json, os, subprocess, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
RS = os.path.join(os.environ.get("CARGO_TARGET_DIR", os.path.join(ROOT, "target")), "debug", "ms-syntax")
cases = []
for exp in sorted(glob.glob(ROOT + "/tests/conformance/fixtures/**/*.expected.json", recursive=True)):
    j = json.load(open(exp))
    if j.get("phase") != "parse":
        continue
    cases.append((exp[: -len(".expected.json")] + ".ms", j["expected"]))
out = b""
for i in range(0, len(cases), 300):
    out += subprocess.run([RS, "batch"] + [c[0] for c in cases[i : i + 300]], capture_output=True).stdout
got, at = {}, 0
while at < len(out):
    nl = out.index(b"\n", at)
    path, diag, status, n = out[at:nl].decode().split("\t")
    got[path] = (diag, status, out[nl + 1 : nl + 1 + int(n)].decode()); at = nl + 1 + int(n)
bad = 0
for path, e in cases:
    diag, status, text = got[path]
    want = [d for d in e["diagnostics"] if d["phase"] == "parse"]
    problems = []
    if want:
        have = json.loads(diag) if diag != "ok" else None
        k = lambda d: (d["code"], d["message"], d["position"]["line"], d["position"]["column"], d["position"]["offset"])
        if have is None or k(have) != k(want[0]):
            problems.append(f"diagnostic want {want[0]['message']!r} got {diag[:200]}")
    elif diag != "ok":
        problems.append(f"unexpected parse error {diag[:200]}")
    if "fmt" in e and e["fmt"] is not None:
        lines = text.split("\n")  # the recorder drops the `# conform:` header from the formatted source
        while lines and lines[0].startswith("# conform:"):
            lines.pop(0)
        if status != "fmt" or "\n".join(lines) != e["fmt"]:
            problems.append("fmt differs")
    if problems:
        bad += 1
        if bad <= 15:
            print(os.path.relpath(path, ROOT), problems)
print(len(cases), "fixtures,", bad, "mismatches")
sys.exit(1 if bad else 0)
