#!/usr/bin/env python3
"""Compare allocating encoding APIs; pass baseline MS, proposed MS and C binaries."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import random
import statistics
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('baseline', type=Path)
parser.add_argument('proposed', type=Path)
parser.add_argument('c', type=Path)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--pairs', type=int, default=11)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
os.sched_setaffinity(0, {max(os.sched_getaffinity(0))})
binaries = {'baseline': args.baseline.resolve(), 'proposed': args.proposed.resolve(),
            'C-exact': args.c.resolve(), 'C-grow': args.c.resolve()}
cases = []

def add(op, name, raw):
    expected = raw.hex().encode() if op == 'hex' else base64.b64encode(raw)
    inp, out = args.output / (name + '.in'), args.output / (name + '.out')
    inp.write_bytes(raw)
    out.write_bytes(expected)
    cases.append(dict(name=name, op=op, input=str(inp.resolve()), expected=str(out.resolve()),
                      input_bytes=len(raw), output_bytes=len(expected)))

rng = random.Random(8675309)
for size in [0, 1, 2, 3, 13, 64, 1024, 65536, 1048576]:
    raw = rng.randbytes(size)
    for op in ['hex', 'b64']:
        add(op, f'{op}-random-{size}', raw)
for op in ['hex', 'b64']:
    add(op, f'{op}-zeros-65536', bytes(65536))
rng = random.Random(8761)
for size in [12287, 12288, 12289, 65535, 65537]:
    add('b64', f'b64-boundary-{size}', rng.randbytes(size))
for size in [8191, 8192, 8193, 16383, 16384, 16385]:
    add('hex', f'hex-boundary-{size}', rng.randbytes(size))

rows = []

def run(case, variant, count):
    op = case['op'] + ('grow' if variant == 'C-grow' else '')
    command = [str(binaries[variant]), op, case['input'], case['expected'],
               str(count), 'OK', str(2**63-1)]
    result = subprocess.run(command, text=True, capture_output=True, check=True)
    n, elapsed, checksum, warm = map(int, result.stdout.strip().split(','))
    unit = case['output_bytes'] + 1
    assert n == count and checksum == n * unit and warm == max(1, n//10) * unit
    return dict(command=command, count=n, ns=elapsed, ns_per_call=elapsed/n,
                checksum=checksum)

for case in cases:
    count = 100
    while True:
        shortest = min(run(case, v, count)['ns'] for v in binaries)
        if shortest >= 20_000_000 or count >= 10_000_000:
            break
        count = min(10_000_000, max(count+1, int(count*25_000_000/max(1, shortest))))
    case['count'] = count
(args.output / 'cases.json').write_text(json.dumps(cases, indent=2))
metadata = dict(cpu_affinity=sorted(os.sched_getaffinity(0)), pairs=args.pairs,
                hashes={str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in binaries.values()})
(args.output / 'metadata.json').write_text(json.dumps(metadata, indent=2))
for pair in range(args.pairs):
    for case in cases:
        order = list(binaries) if pair % 2 == 0 else list(reversed(binaries))
        for variant in order:
            rows.append(dict(case=case['name'], variant=variant, pair=pair,
                             **run(case, variant, case['count'])))
    (args.output / 'samples.json').write_text(json.dumps(rows, indent=2))
    print('pair', pair, flush=True)
for case in cases:
    times = {v: statistics.median(x['ns_per_call'] for x in rows
                                if x['case'] == case['name'] and x['variant'] == v)
             for v in binaries}
    ratios = [next(x['ns_per_call'] for x in rows if x['case'] == case['name'] and
                   x['variant'] == 'proposed' and x['pair'] == i) /
              next(x['ns_per_call'] for x in rows if x['case'] == case['name'] and
                   x['variant'] == 'baseline' and x['pair'] == i) for i in range(args.pairs)]
    print(case['name'], times, 'paired ratio', statistics.median(ratios),
          'range', min(ratios), max(ratios))
