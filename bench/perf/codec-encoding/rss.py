#!/usr/bin/env python3
"""Sample exec-specific Linux VmHWM; do not confuse fork-inherited wait4 RSS."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

root = Path(sys.argv[1])
binaries = [Path(p).resolve() for p in sys.argv[2:]]
cases = [c for c in json.loads((root / 'cases.json').read_text())
         if c['name'] in ['hex-random-13', 'b64-random-13',
                          'hex-random-65536', 'b64-random-65536',
                          'hex-random-1048576', 'b64-random-1048576']]
rows = []
for pair in range(5):
    for case in cases:
        count = 1000000 if case['input_bytes'] == 13 else (1000 if case['input_bytes'] == 65536 else 100)
        for binary in (binaries if pair % 2 == 0 else list(reversed(binaries))):
            command = [str(binary), case['op'], case['input'], case['expected'], str(count), 'OK', str(2**63-1)]
            process = subprocess.Popen(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            peak, samples = 0, 0
            while process.poll() is None:
                try:
                    if os.readlink(f'/proc/{process.pid}/exe') == str(binary):
                        status = Path(f'/proc/{process.pid}/status').read_text()
                        hwm = next(int(line.split()[1]) for line in status.splitlines() if line.startswith('VmHWM:'))
                        peak = max(peak, hwm)
                        samples += 1
                except (FileNotFoundError, ProcessLookupError, StopIteration):
                    pass
                time.sleep(.001)
            stdout, stderr = process.communicate()
            assert process.returncode == 0, (stdout, stderr)
            n, elapsed, checksum, warm = map(int, stdout.strip().split(','))
            unit = case['output_bytes']+1
            assert n == count and checksum == n*unit and warm == max(1,n//10)*unit
            assert peak > 0 and samples > 0
            rows.append(dict(case=case['name'], binary=str(binary), pair=pair,
                             peak_rss_kib=peak, samples=samples, command=command))
    (root / 'rss.json').write_text(json.dumps(rows, indent=2))
