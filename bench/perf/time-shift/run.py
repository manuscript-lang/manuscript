"""Paired production executable timings with an independent integer checksum oracle."""
import hashlib
import json
import platform
import random
import resource
import statistics
import subprocess
import sys
import time
from pathlib import Path


def expected(kind, count, rounds):
    total = 0
    for i in range(count):
        seconds, nanos = 1700000000 + i, i * 7919 % 10**9
        delta = (i % 17 - 8) * 123456789
        if kind == "zero":
            delta = 0
        if kind == "normalize":
            nanos = -1
        if kind == "wide":
            delta = 2**63 - 1 if i % 2 == 0 else -(2**63)
        if kind == "fallback":
            seconds, nanos, delta = 0, 2**63 - 1, 2**63 - 1
        if kind == "fallback_negative":
            seconds, nanos, delta = 0, -(2**63), -(2**63)
        if kind == "fallback_multiple":
            seconds, nanos, delta = 0, 9223372036000000000, 10**9
        if kind == "carry_max":
            nanos, delta = 10**9 - 1, 2**63 - 1
        if kind == "error":
            total += 1
        elif kind == "parse":
            total += 1772368245 + 123000000
        elif kind == "format":
            # These contemporary UTC seconds always occupy 20 RFC3339 bytes,
            # plus a dot and the fraction after trailing-zero removal.
            fraction = f"{nanos:09}".rstrip("0")
            total += 20 + (1 + len(fraction) if nanos else 0)
        else:
            s, ns = divmod(seconds * 10**9 + nanos + delta, 10**9)
            assert -62135596800 <= s <= 253402300799
            total += s + ns
    return total * rounds


def invoke(binary, kind, count, rounds):
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    start = time.perf_counter_ns()
    p = subprocess.run(["taskset", "-c", "0", binary, kind, str(count), str(rounds)],
                       text=True, capture_output=True, check=True)
    wall = time.perf_counter_ns() - start
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    row = p.stdout.split()
    assert len(row) == 5 and row[:3] == [kind, str(count), str(rounds)], p.stdout
    ns, checksum = map(int, row[3:])
    assert checksum == expected(kind, count, rounds), p.stdout
    assert ns > 0 and not p.stderr, p.stderr
    return dict(stdout=p.stdout, elapsed_ns=ns, wall_ns=wall, checksum=checksum,
                minor_faults=after.ru_minflt-before.ru_minflt,
                major_faults=after.ru_majflt-before.ru_majflt)


def main():
    before, after, output = sys.argv[1:4]
    pairs = int(sys.argv[4]) if len(sys.argv) > 4 else 12
    metadata = dict(platform=platform.platform(), cpu=Path('/proc/cpuinfo').read_text(),
                    cpu_max=Path('/sys/fs/cgroup/cpu.max').read_text(), affinity=[0],
                    source_sha256=hashlib.sha256(Path(__file__).with_name('main.ms').read_bytes()).hexdigest(),
                    binaries={p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in [before,after]},
                    argv=sys.argv, revision=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
                    diff=subprocess.check_output(['git','diff','--','crates/ms-std-time/src/core_time.rs'],text=True))
    cases = [(kind, n) for kind in ['small','zero','wide','normalize','fallback','fallback_negative',
                                  'fallback_multiple','carry_max','error','pipeline','parse','format']
             for n in [1,32,4096]]
    raw = dict(metadata=metadata, samples=[], calibration=[])
    workloads = []
    for kind, n in cases:
        r = invoke(before, kind, n, max(1, 100000//n))
        rounds = max(1, int(max(1, 100000//n) * 60_000_000 / r['elapsed_ns']))
        raw['calibration'].append(dict(kind=kind,count=n,rounds=rounds,measurement=r))
        workloads.append((kind,n,rounds))
    rng = random.Random(20261110)
    for pair in range(pairs):
        rng.shuffle(workloads)
        for kind,n,rounds in workloads:
            for side in ([0,1] if pair%2 == 0 else [1,0]):
                sample = invoke([before,after][side],kind,n,rounds)
                raw['samples'].append(dict(pair=pair,side=side,kind=kind,count=n,rounds=rounds,**sample))
        Path(output).write_text(json.dumps(raw,indent=2)+'\n')
        print(f'pair {pair+1}/{pairs}',flush=True)
    for kind,n in cases:
        med = [statistics.median(r['elapsed_ns']/(r['count']*r['rounds']) for r in raw['samples']
                                if r['kind']==kind and r['count']==n and r['side']==side) for side in [0,1]]
        print(kind,n,*[round(v,3) for v in med],round(med[1]/med[0],3))


if __name__ == '__main__':
    main()
