"""Preselected noise/patch crossover; both conditions run in each case/round."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import resource
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--base', required=True)
parser.add_argument('--candidate', required=True)
parser.add_argument('--inputs', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--rounds', type=int, default=61)
args = parser.parse_args()
assert not args.output.exists()
cases = {'optional-retry': 0, 'callable-explicit-1-1': 0,
         'reject-callback-arity': 2, 'callable-inferred-256-1000': 0}
cpu = min(os.sched_getaffinity(0))
digest = lambda data: hashlib.sha256(data).hexdigest()
result = {'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
          'patch': subprocess.check_output(['git', 'diff', '--', 'crates/ms-check/src/inference.rs'], text=True),
          'uname': list(os.uname()), 'cpuinfo': Path('/proc/cpuinfo').read_text(), 'cpu': cpu,
          'rounds': args.rounds, 'samples': [], 'inputs': {}, 'oracles': {},
          'binaries': {label: {'path': path, 'sha256': digest(Path(path).read_bytes())}
                       for label, path in [('base', args.base), ('candidate', args.candidate)]},
          'protocol': 'one warmup per case/binary, then seeded shuffled cases and AA/AB condition order per round; alternating pair order; all processes CPU pinned'}
oracles = {}
for name, expected_count in cases.items():
    path = args.inputs / (name + '.ms')
    result['inputs'][name] = {'path': str(path), 'source': path.read_text(), 'sha256': digest(path.read_bytes())}
    run = subprocess.run([args.base, 'check', str(path), '--json'], capture_output=True, timeout=90)
    assert run.returncode == (1 if expected_count else 0) and run.stderr == b''
    assert len(json.loads(run.stdout)['diagnostics']) == expected_count
    oracles[name] = run.returncode, run.stdout, run.stderr
    result['oracles'][name] = {'exit': run.returncode, 'stdout': run.stdout.decode(), 'stderr': run.stderr.decode()}


def measure(name, condition, label, binary, trial):
    path = args.inputs / (name + '.ms')
    command = ['taskset', '-c', str(cpu), binary, 'check', str(path), '--json']
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    start = time.perf_counter_ns()
    run = subprocess.run(command, capture_output=True, timeout=90)
    elapsed = time.perf_counter_ns() - start
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    sample = {'round': trial, 'case': name, 'condition': condition, 'label': label,
              'command': command, 'wall_ns': elapsed,
              'user_seconds': after.ru_utime - before.ru_utime,
              'system_seconds': after.ru_stime - before.ru_stime,
              'minor_faults': after.ru_minflt - before.ru_minflt,
              'major_faults': after.ru_majflt - before.ru_majflt,
              'exit': run.returncode, 'stdout': run.stdout.decode(), 'stderr': run.stderr.decode()}
    result['samples'].append(sample)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    assert (run.returncode, run.stdout, run.stderr) == oracles[name], sample


for name in cases:
    for label, path in [('base', args.base), ('candidate', args.candidate)]:
        measure(name, 'warmup', label, path, -1)
rng = random.Random(651283)
for trial in range(args.rounds):
    order = list(cases)
    rng.shuffle(order)
    for index, name in enumerate(order):
        conditions = ['AA', 'AB']
        rng.shuffle(conditions)
        for condition in conditions:
            binaries = [('base', args.base), ('candidate', args.base if condition == 'AA' else args.candidate)]
            if (trial + index) % 2:
                binaries.reverse()
            for label, binary in binaries:
                measure(name, condition, label, binary, trial)
    print(f'round {trial} complete', flush=True)
