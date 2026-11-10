#!/usr/bin/env python3
"""Paired host-side orchestration of the release Rust query harness."""
import csv
import os
from pathlib import Path
import resource
import statistics
import subprocess
import sys

before, after, output = sys.argv[1:4]
samples = int(sys.argv[4]) if len(sys.argv) > 4 else 9
cpu = min(os.sched_getaffinity(0))
cases = [(m, n, 'ascii') for m in ['hover-full-name-first', 'hover-full-name', 'hover-full', 'hover-full-symbol', 'symbols', 'completion', 'hover-name', 'definition-symbol'] for n in [1, 100, 1000, 4000]]
cases += [(m, 1000, shape) for shape in ['crlf', 'unicode'] for m in ['hover-full-name', 'hover-full-symbol']]
if os.environ.get('LSP_BENCH_CASES'):
    selected = set(os.environ['LSP_BENCH_CASES'].split(','))
    cases = [case for case in cases if ':'.join(map(str, case)) in selected]
    assert cases, selected

def run(binary, mode, count, rounds, shape):
    start = resource.getrusage(resource.RUSAGE_CHILDREN)
    p = subprocess.run(['taskset', '-c', str(cpu), binary, mode, str(count), str(rounds), shape], check=True, capture_output=True, text=True, timeout=120)
    end = resource.getrusage(resource.RUSAGE_CHILDREN)
    row = p.stdout.strip().split(',')
    assert len(row) == 8, p.stdout
    return row, end.ru_minflt-start.ru_minflt, end.ru_majflt-start.ru_majflt

with Path(output).open('w') as f:
    writer = csv.writer(f)
    writer.writerow(['mode','count','rounds','shape','elapsed_ns','fingerprint','source_bytes','rss_kib','variant','sample','minor_faults','major_faults'])
    for mode,count,shape in cases:
        row,_,_ = run(before,mode,count,1,shape)
        rounds = max(1, min(10000, int(int(os.environ.get("LSP_BENCH_NS", "30000000"))/max(1,int(row[4])))))
        identity = row[5:7]
        times = {'before':[], 'after':[]}
        for sample in range(samples):
            for variant,binary in ([('before',before),('after',after)] if sample%2==0 else [('after',after),('before',before)]):
                row,minor,major = run(binary,mode,count,rounds,shape)
                assert row[5:7] == identity, (mode,count,shape,variant,row[5:7],identity)
                writer.writerow(row+[variant,sample,minor,major]);f.flush()
                times[variant].append(int(row[4])/rounds/1000)
        a,b = [statistics.median(times[v]) for v in ['before','after']]
        print(mode,count,shape,round(a,3),round(b,3),round(b/a,4),flush=True)
