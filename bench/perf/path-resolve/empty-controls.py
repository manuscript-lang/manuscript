"""Compare unchanged baseline source and current stdlib in one LLVM executable."""
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import tempfile

compiler = str(Path(sys.argv[1]).resolve())
output = Path(sys.argv[2])
os.sched_setaffinity(0, {int(os.environ.get('BENCH_CPU', '4'))})
revision = 'ff4ce5edff87e46edf1f1f105bc93cd1b6236217'
source = subprocess.check_output(['git', 'show', revision + ':stdlib/os/path.ms'], text=True)
# App modules cannot import this private native. No resolver code calls the stub.
source = source.replace('\tmsstd_path_matches_glob from "@std/internal/path.ms",\n', '')
source = source.replace('return msstd_path_matches_glob(windows, path, pattern)', 'return error(invalid_input())')
source = source.replace('export fn posix()', 'export fn baseline()')
rows = []
with tempfile.TemporaryDirectory() as directory:
    folder = Path(directory)
    (folder / 'baseline.ms').write_text(source)
    (folder / 'empty.ms').write_text(Path(__file__).with_name('empty-controls.ms.in').read_text())
    binary = folder / 'empty'
    subprocess.run([compiler, 'build', str(folder / 'empty.ms'), '--build-type', 'Release', '-o', str(binary)], check=True)
    digest = hashlib.sha256(binary.read_bytes()).hexdigest()
    for n in [0, 1, 4, 32, 256]:
        samples = []
        for i in range(21):
            row = {}
            for side in (['base', 'new'] if i % 2 == 0 else ['new', 'base']):
                result = subprocess.run([str(binary), side, str(n), '100000'], capture_output=True, text=True, check=True)
                ns, checksum = map(int, result.stdout.split())
                assert checksum == 500000
                row[side] = ns / 100000
                row[side + '_checksum'] = checksum
            samples.append(row)
        rows.append(dict(n=n, repeats=100000, samples=samples))
        print(n, *[round(statistics.median(r[k] for r in samples), 2) for k in ['base', 'new']], flush=True)
output.write_text(json.dumps(dict(baseline=revision, sha256=digest, rows=rows), indent=2) + '\n')
