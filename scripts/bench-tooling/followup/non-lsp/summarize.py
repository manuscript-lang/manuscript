import json
import re
import statistics
from pathlib import Path

root = Path(__file__).parent
samples = {}
for line in (root / 'bench.txt').read_text().splitlines():
    match = re.match(r'(Benchmark\S+)\s+\d+\s+([0-9.]+) ns/op.*?\s([0-9.]+) B/op\s+([0-9.]+) allocs/op', line)
    if not match:
        continue
    name = re.sub(r'-\d+$', '', match[1])
    samples.setdefault(name, []).append(dict(ns_op=float(match[2]), bytes_op=float(match[3]), allocs_op=float(match[4])))

out = {}
for name, data in samples.items():
    out[name] = {'samples': len(data)}
    for metric in ['ns_op', 'bytes_op', 'allocs_op']:
        values = [row[metric] for row in data]
        out[name][metric] = {'median': statistics.median(values), 'min': min(values), 'max': max(values)}
if not out:
    raise SystemExit('No benchmark samples parsed; inspect bench.txt')
(root / 'summary.json').write_text(json.dumps(out, indent=2) + '\n')
print(json.dumps(out, indent=2))
