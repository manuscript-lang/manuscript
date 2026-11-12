#!/usr/bin/env python3
"""A/A timing controls for previously calibrated cases, without rebuilding."""
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
binaries = [Path(p).resolve() for p in sys.argv[2:]]
os.sched_setaffinity(0, {max(os.sched_getaffinity(0))})
cases = [c for c in json.loads((root / 'cases.json').read_text())
         if c['name'] in ['hex-random-13', 'b64-random-13',
                          'hex-random-65536', 'b64-random-65536']]
rows = []
for pair in range(7):
    for case in cases:
        for binary in binaries:
            for slot in (['A', 'B'] if pair % 2 == 0 else ['B', 'A']):
                command = [str(binary), case['op'], case['input'], case['expected'],
                           str(case['count']), 'OK', str(2**63-1)]
                result = subprocess.run(command, text=True, capture_output=True, check=True)
                n, ns, checksum, warm = map(int, result.stdout.strip().split(','))
                unit = case['output_bytes']+1
                assert n == case['count'] and checksum == n*unit and warm == max(1,n//10)*unit
                rows.append(dict(case=case['name'], binary=str(binary), pair=pair,
                                 slot=slot, ns=ns, count=n, checksum=checksum))
    (root / 'aa.json').write_text(json.dumps(rows, indent=2))
