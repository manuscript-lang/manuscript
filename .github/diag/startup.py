"""Times ms process startup and a few commands; temporary CI diagnosis."""
import os, subprocess, sys, time, pathlib
ms = sys.argv[1]
work = pathlib.Path(sys.argv[2]); work.mkdir(parents=True, exist_ok=True)
(work / "t.ms").write_text("fn main() Unit:\n    let _x = 1\n")
def t(label, cmd, n=20):
    subprocess.run(cmd, cwd=work, capture_output=True)
    s = time.perf_counter()
    for _ in range(n):
        r = subprocess.run(cmd, cwd=work, capture_output=True)
    ms_ = (time.perf_counter() - s) / n * 1000
    print(f"{label:28s} {ms_:8.1f} ms  exit {r.returncode}", flush=True)
exe = ".exe" if os.name == "nt" else ""
t("python -c pass", [sys.executable, "-c", "pass"])
t("ms --version", [ms, "--version"])
t("ms fmt --check", [ms, "fmt", "--check", "t.ms"])
t("ms check", [ms, "check", "t.ms"])
t("ms build (debug)", [ms, "build", "t.ms", "-o", "t" + exe], n=5)
t("built program", [str(work / ("t" + exe))])
