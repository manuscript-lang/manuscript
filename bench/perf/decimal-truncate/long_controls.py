#!/usr/bin/env python3
"""Predeclared longer common-path controls, retaining candidate and A/A samples."""
import json
from pathlib import Path
import runpy
import sys
import time

run = runpy.run_path(str(Path(__file__).parents[1] / 'decimal-conversions/repeat.py'))['run']
before, after = sys.argv[1:3]
cases = [
    ('negate', 25000001, 12345),
    ('negate', 25000001, -9223372036854775808),
    ('int', 5000000, 0),
    ('uint', 5000000, 0),
    ('stream', 2000000, 0),
    ('add-round', 200000, 0),
]
binaries = [('before', before), ('after', after), ('aa', before), ('aa-after', after)]
for case in cases:
    for phase in range(-1, 8):
        offset = phase % 4
        order = binaries[offset:] + binaries[:offset]
        if phase // 4 % 2:
            order.reverse()
        for label, binary in order:
            start = time.time_ns()
            row = run(binary, *case)
            row.update(binary=label, operation=case[0], count=case[1], seed=case[2],
                       phase=phase, start_unix_ns=start, end_unix_ns=time.time_ns())
            print(json.dumps(row), flush=True)
