#!/usr/bin/env python3
"""Bounded independent BigInt/primitive discovery; every result is oracle checked."""
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import time

before, after, rust = sys.argv[1:4]
cases = [('factorial', 0, 10000), ('factorial', 20, 1), ('factorial', 20, 100000),
         ('factorial', 1000, 1), ('factorial', 1000, 200),
         ('factorial', 1500, 1), ('factorial', 1500, 100), ('lcg', 1, 1), ('lcg', 1000000, 5)]
binaries = [('before', before, []), ('after', after, []),
            ('rust', rust, []), ('rust-borrowed', rust, ['borrowed']), ('aa', before, [])]
for label, binary, _ in binaries:
    print(json.dumps(dict(artifact=label, sha256=hashlib.sha256(Path(binary).read_bytes()).hexdigest())), flush=True)
for operation, n, count in cases:
    if operation == 'factorial':
        value = math.factorial(n)
    else:
        value = 1
        for _ in range(n):
            value = value * 48271 % 2147483647
    result_text = str(value)
    cycles, tail = divmod(count, 7)
    expected = (value % 1000003) * (cycles * 28 + tail * (tail + 1) // 2)
    for phase in range(-1, 10):
        offset = phase % 5
        order = binaries[offset:] + binaries[:offset]
        if phase // 5 % 2:
            order.reverse()
        for label, binary, extra in order:
            started = time.time_ns()
            output = subprocess.run([binary, operation, str(n), str(count), *extra],
                                    capture_output=True, text=True, check=True, timeout=90)
            ended = time.time_ns()
            row = re.fullmatch(r'case=([a-z]+) n=(\d+) count=(\d+) ns=(\d+) checksum=(\d+) result=(\d+)\n', output.stdout)
            if output.stderr or not row or (row[1], int(row[2]), int(row[3])) != (operation, n, count):
                raise RuntimeError('malformed producer')
            if int(row[5]) != expected or row[6] != result_text or not 0 <= int(row[4]) <= ended-started:
                raise RuntimeError('wrong arithmetic or timing')
            print(json.dumps(dict(binary=label, operation=operation, n=n, count=count, phase=phase,
                                  ns_op=int(row[4])/count, checksum=expected, result_digits=len(result_text),
                                  result_sha256=hashlib.sha256(result_text.encode()).hexdigest(),
                                  start_unix_ns=started, end_unix_ns=ended)), flush=True)
