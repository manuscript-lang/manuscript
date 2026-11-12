"""Longer A/B and A/A control for the long fixed-offset pattern."""
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
os.sched_setaffinity(0, {min(os.sched_getaffinity(0))})
env = dict(os.environ, MS_CPU_LEVEL="baseline", LC_ALL="C", TZ="UTC")
rows = []
for comparison in ["ab", "aa"]:
    ratios = []
    for repetition in range(28):
        values = {}
        outputs = []
        for side in ([0, 1] if repetition % 2 == 0 else [1, 0]):
            variant = "new" if side == 1 and comparison == "ab" else "base"
            result = subprocess.run(
                [str(root / variant), "YYYY-MM-DD🙂 " * 128, "+05:30", "50000",
                 "1709251199", "123456789"],
                capture_output=True, check=True, env=env,
            )
            elapsed, checksum = map(int, result.stdout.split())
            assert checksum == len(result.stderr[:-1]) * 50000
            outputs.append(result.stderr)
            values[side] = elapsed
            rows.append({"comparison": comparison, "rep": repetition,
                         "side": side, "variant": variant, "ns": elapsed})
        assert outputs[0] == outputs[1]
        if repetition >= 3:
            ratios.append(values[1] / values[0])
    print(comparison, statistics.median(ratios), min(ratios), max(ratios), flush=True)
(root / "long-confirm.json").write_text(json.dumps(rows, indent=2) + "\n")
