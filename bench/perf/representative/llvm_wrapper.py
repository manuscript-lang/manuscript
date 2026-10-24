#!/usr/bin/env python3
"""Log actual LLVM children; only used for diagnostic stage runs, not CLI wall timing."""
import json
import os
import pathlib
import subprocess
import sys
import time

tool = pathlib.Path(sys.argv[0]).name
command = [str(pathlib.Path(os.environ["REAL_LLVM_TOOLS"]) / tool), *sys.argv[1:]]
if os.environ.get("LLVM_TIME_PASSES") == "1":
    command.append("-time-passes")
report = None
if os.environ.get("LLVM_TIME_PASSES") == "1":
    # The compiler captures and discards successful tool stderr; preserve diagnostics here.
    report = open(os.environ["LLVM_METRICS"] + f".{tool}-passes.txt", "w")
start = time.perf_counter()
child = subprocess.Popen(command, stderr=report)
_, status, usage = os.wait4(child.pid, 0)
child.returncode = os.waitstatus_to_exitcode(status)
if report is not None:
    report.close()
with open(os.environ["LLVM_METRICS"], "a") as log:
    log.write(json.dumps(dict(tool=tool, command=command, wall_s=time.perf_counter()-start,
                             user_s=usage.ru_utime, system_s=usage.ru_stime,
                             maxrss_kib=usage.ru_maxrss, exit=child.returncode)) + "\n")
sys.exit(child.returncode)
