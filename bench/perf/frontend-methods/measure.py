import csv, io, json, os, pathlib, random, statistics, subprocess, sys, time
bench = pathlib.Path(sys.argv[1]).resolve()
files = [pathlib.Path(p).resolve() for p in sys.argv[2:]]
if hasattr(os, 'sched_getaffinity'):
    os.sched_setaffinity(0, {min(os.sched_getaffinity(0))})
jobs = [(trial, path) for trial in range(5) for path in files]
random.Random(1729).shuffle(jobs)
all_rows = []
for trial, path in jobs:
    start = time.perf_counter()
    r = subprocess.run([str(bench), str(path), '6'], capture_output=True, text=True, timeout=30)
    if r.returncode: raise RuntimeError(r.stderr)
    all_rows.append(dict(file=path.name, trial=trial, wall_s=time.perf_counter()-start,
                         init=r.stderr, rows=list(csv.DictReader(io.StringIO(r.stdout)))))
    pathlib.Path('raw.json').write_text(json.dumps(all_rows, indent=2))
for path in files:
    runs = [r for r in all_rows if r['file'] == path.name]
    warm = [float(x['check_ms']) for r in runs for x in r['rows'][1:]]
    cold = [float(r['rows'][0]['check_ms']) for r in runs]
    print(path.name, 'bytes', runs[0]['rows'][0]['bytes'], 'warm median/min/max ms',
          *[round(f(warm), 3) for f in (statistics.median, min, max)],
          'first-check median ms', round(statistics.median(cold), 3), flush=True)
