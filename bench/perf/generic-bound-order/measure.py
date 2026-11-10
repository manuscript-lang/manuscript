#!/usr/bin/env python3
"""Paired whole-process frontend controls; standard library/startup are included."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import statistics
import subprocess
import tempfile
import time

p = argparse.ArgumentParser()
p.add_argument('before', type=Path)
p.add_argument('after', type=Path)
p.add_argument('output', type=Path)
p.add_argument('--pairs', type=int, default=30)
p.add_argument('--same-binary', action='store_true')
p.add_argument('--warm', action='store_true')
a = p.parse_args()
bins = {'before': a.before.resolve(), 'after': a.after.resolve()}
if a.same_binary:
    bins['after'] = bins['before']
cpu = min(os.sched_getaffinity(0))
os.sched_setaffinity(0, {cpu})
reader = 'interface Reader[A]:\n    fn read() A\n\n'
box = 'type Box[A]:\n    value: A\n\n'
cases = {
    'tiny': 'fn entry() Int: return 1\n',
    'concrete_250': '\n'.join(f'fn f{i}(v: Int) Int: return v + 1' for i in range(250)) + '\n',
    'generic_1': reader + 'fn read[T: Reader[Int]](v: T) Int: return v.read()\n',
    'nested_250': box + reader + '\n'.join(f'fn f{i}[T: Reader[Box[Int]]](v: T) Int: return v.read().value' for i in range(250)) + '\n',
    'defaults_100': '\n'.join(f'fn f{i}[T: Equal = Int](v: T) Bool: return v == v' for i in range(100)) + '\n',
}
for size in [250, 500, 1000]:
    cases[f'generic_{size}'] = reader + '\n'.join(f'fn f{i}[T: Reader[Int]](v: T) Int: return v.read()' for i in range(size)) + '\n'
expected = b'{"format":1,"diagnostics":[]}\n'
samples = []
rng = random.Random(3489)
with tempfile.TemporaryDirectory(prefix='generic-bound-order-') as tmp:
    files = {}
    for name, source in cases.items():
        files[name] = Path(tmp) / (name + '.ms')
        files[name].write_text(source)
    def run(name, side, pair, warmup=False):
        start = time.perf_counter_ns()
        iterations = 100 if name in ['tiny', 'generic_1'] else 10
        command = [str(bins[side]), str(files[name]), str(iterations)] if a.warm else [str(bins[side]), '--json', str(files[name])]
        result = subprocess.run(command, capture_output=True, timeout=30)
        elapsed = time.perf_counter_ns() - start
        if a.warm and result.returncode == 0:
            measured = json.loads(result.stdout)
            assert set(measured) == {'iterations', 'diagnostics', 'elapsed_ns'}
            assert measured['iterations'] == iterations and measured['diagnostics'] == [] and measured['elapsed_ns'] > 0
            elapsed = measured['elapsed_ns'] / iterations
            result.stdout = expected
        if (result.returncode, result.stdout, result.stderr) != (0, expected, b''):
            raise RuntimeError((name, side, result.returncode, result.stdout, result.stderr))
        if not warmup:
            samples.append({'case': name, 'pair': pair, 'side': side, 'ns': elapsed, 'exit': 0, 'validated_diagnostics_sha256': hashlib.sha256(result.stdout).hexdigest(), 'stderr_bytes': 0})
    for name in cases:
        for side in bins:
            run(name, side, -1, True)
    for pair in range(a.pairs):
        order = list(cases)
        rng.shuffle(order)
        for name in order:
            for side in (('before', 'after') if pair % 2 == 0 else ('after', 'before')):
                run(name, side, pair)
summary = {}
for name in cases:
    times = {side: [s['ns'] for s in samples if s['case'] == name and s['side'] == side] for side in bins}
    by_pair = [{s['side']: s['ns'] for s in samples if s['case'] == name and s['pair'] == pair} for pair in range(a.pairs)]
    summary[name] = {'before_median_ms': statistics.median(times['before']) / 1e6, 'after_median_ms': statistics.median(times['after']) / 1e6, 'median_pair_ratio': statistics.median(v['after'] / v['before'] for v in by_pair), 'after_faster_pairs': sum(v['after'] < v['before'] for v in by_pair)}
result = {'base': '754aa75a3c5fb66a54c19047cf9f2bb45d1a9db4', 'platform': platform.platform(), 'cpu': cpu, 'cpuinfo': next((l.strip() for l in Path('/proc/cpuinfo').read_text().splitlines() if l.startswith('model name')), ''), 'pairs': a.pairs, 'same_binary': a.same_binary, 'warm_session': a.warm, 'warm_iterations': {'tiny': 100, 'generic_1': 100, 'other_cases': 10} if a.warm else None, 'binaries': {side: {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()} for side, path in bins.items()}, 'sources': cases, 'expected_stdout': expected.decode(), 'samples': samples, 'summary': summary}
a.output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(summary, indent=2))
