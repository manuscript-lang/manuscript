#!/usr/bin/env python3
"""Paired frontend-process controls; build both revisions before running."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import statistics
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('base', type=Path)
parser.add_argument('fixed', type=Path)
parser.add_argument('--pairs', type=int, default=20)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
binaries = {'base': args.base.resolve(), 'fixed': args.fixed.resolve()}
if hasattr(os, 'sched_getaffinity'):
    cpu = min(os.sched_getaffinity(0))
    os.sched_setaffinity(0, {cpu})
else:
    cpu = None

def digest(data):
    return hashlib.sha256(data).hexdigest()

repo = Path(__file__).resolve().parents[3]
sources = {'hello': (repo / 'examples/hello/src/main.ms').read_text()}
for count in (1, 64):
    ordinary = ''
    affected = 'import panic from "@std/core.ms"\n'
    for i in range(count):
        ordinary += f'''fn ordinary{i}(values: List[Int], limit: Int) Int:
    var total = 0
    for value in values:
        if value > limit:
            break
        if value < 0:
            continue
        total += value
    return total
'''
        # The trailing return makes both versions accept the same source. The
        # regression fixture separately establishes corrected acceptance.
        affected += f'''fn stopped{i}() Int:
    while true:
        if panic("stop"):
            break
    return 0
'''
    sources[f'ordinary-{count}'] = ordinary
    sources[f'affected-{count}'] = affected

report = {'platform': platform.platform(), 'cpu': cpu, 'pairs': args.pairs,
          'binary_sha256': {k: digest(p.read_bytes()) for k, p in binaries.items()},
          'cases': {}}
with tempfile.TemporaryDirectory(prefix='flow-perf-') as folder:
    for name, source in sources.items():
        path = Path(folder) / (name + '.ms')
        path.write_text(source)
        samples = {'base': [], 'fixed': []}
        cpu_samples = {'base': [], 'fixed': []}
        expected = None
        for trial in range(-2, args.pairs):
            order = ('base', 'fixed') if trial % 2 == 0 else ('fixed', 'base')
            for version in order:
                before_cpu = resource.getrusage(resource.RUSAGE_CHILDREN)
                start = time.perf_counter_ns()
                result = subprocess.run([str(binaries[version]), '--json', str(path)],
                                        capture_output=True, check=True)
                elapsed = time.perf_counter_ns() - start
                after_cpu = resource.getrusage(resource.RUSAGE_CHILDREN)
                cpu_elapsed = round(((after_cpu.ru_utime - before_cpu.ru_utime)
                                     + (after_cpu.ru_stime - before_cpu.ru_stime)) * 1e9)
                assert not result.stderr, result.stderr
                assert json.loads(result.stdout)['diagnostics'] == [], result.stdout
                if expected is None:
                    expected = result.stdout
                assert result.stdout == expected
                if trial >= 0:
                    samples[version].append(elapsed)
                    cpu_samples[version].append(cpu_elapsed)
        ratios = [b / a for a, b in zip(samples['base'], samples['fixed'])]
        report['cases'][name] = {'source': source, 'source_sha256': digest(source.encode()),
                                'output_sha256': digest(expected), 'samples_ns': samples,
                                'cpu_samples_ns': cpu_samples,
                                'median_pair_ratio': statistics.median(ratios),
                                'median_cpu_pair_ratio': statistics.median(
                                    b / a for a, b in zip(cpu_samples['base'], cpu_samples['fixed'])),
                                'median_ns': {k: statistics.median(v) for k, v in samples.items()}}
args.output.write_text(json.dumps(report, indent=2) + '\n')
for name, case in report['cases'].items():
    print(name, case['median_ns'], 'wall ratio', case['median_pair_ratio'],
          'CPU ratio', case['median_cpu_pair_ratio'])
