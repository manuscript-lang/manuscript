from pathlib import Path
import hashlib, json, os, platform, statistics, subprocess, sys, time
# Usage: python3 measure-controls.py PREPARED_DIRECTORY MS_BINARY BASELINE_SHA [LLVM_TOOLS]
root = Path(sys.argv[1]).resolve()
compiler = Path(sys.argv[2]).resolve()

def sha(path):
    with path.open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()

def run(executable, data, output):
    with data.open('rb') as stdin, output.open('wb') as stdout:
        started = time.perf_counter_ns()
        result = subprocess.run([str(executable)], cwd=executable.parent, stdin=stdin, stdout=stdout)
        elapsed = time.perf_counter_ns() - started
    if result.returncode: raise RuntimeError(f'{executable}: exited {result.returncode}')
    return elapsed

report = {'baseline': sys.argv[3],
    'platform': platform.platform(), 'cpu': next(line.split(':',1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')),
    'affinity': sorted(os.sched_getaffinity(0)), 'compiler_sha256': sha(compiler),
    'rust': subprocess.check_output(['rustc','--version'], text=True).strip(),
    'go': subprocess.check_output(['go','version'], text=True).strip(),
    # Backend receipt is collected separately during builds; timing alone cannot identify it.
    'backend_receipt': str(root/'llvm-invocations.jsonl'),
    'repeats': 7, 'cases': []}
if len(sys.argv) > 4:
    llvm_tools = Path(sys.argv[4]).resolve()
    report['llvm_tools'] = {name: {'sha256': sha(llvm_tools/name),
        'version': subprocess.check_output([str(llvm_tools/name), '--version'], text=True).splitlines()[:2]}
        for name in ('opt', 'llc', 'llvm-link')}
for program in ('c03-csv-group-sum','c05-calculator'):
    work = root / program
    versions = {'explicit': work/'ms/app', 'default': work/'ms/default-app', 'go': work/'go/app', 'rust': work/'rs/app'}
    for n in (1, 1000, 10000, 100000):
        if program.startswith('c03'):
            data = b'food,1.20\n"travel,train",2.30\nbad\nfood,0.05\n' * n
            expected = f'food: {125*n//100}.{125*n%100:02d}\ntravel,train: {230*n//100}.{230*n%100:02d}\nskipped: {n}\n'.encode()
        else:
            data = b'1+2*3\n(8-3)*2\n9/0\n1+)\n-7/2\n' * n
            expected = b'7\n10\nerror: division by zero\nerror: syntax\n-3\n' * n
        input_path = work/'in'
        input_path.write_bytes(data)
        expected_hash = hashlib.sha256(expected).hexdigest()
        rows = []
        for version, executable in versions.items():
            output = work/f'control-{version}.out'
            run(executable, input_path, output)
            if output.read_bytes() != expected: raise RuntimeError(f'{program}/{n}/{version} wrong warmup output')
        names = tuple(versions)
        for trial in range(7):
            offset = trial % len(names)
            for version in names[offset:] + names[:offset]:
                output = work/f'control-{version}.out'
                elapsed = run(versions[version], input_path, output)
                if output.read_bytes() != expected: raise RuntimeError(f'{program}/{n}/{version} wrong trial output')
                rows.append({'trial':trial, 'version':version, 'elapsed_ns':elapsed})
        stats = {}
        for v in names:
            samples = [row['elapsed_ns']/1e6 for row in rows if row['version']==v]
            stats[v] = {'min_ms':min(samples),'median_ms':statistics.median(samples),'max_ms':max(samples)}
        case = {'program':program,'groups':n,'input_bytes':len(data),'input_sha256':sha(input_path),'output_sha256':expected_hash,
                'binaries_sha256':{v:sha(p) for v,p in versions.items()},'stats':stats,'samples':rows}
        report['cases'].append(case)
        print(program,n,'; '.join(f'{v}: {s["min_ms"]:.3f}/{s["median_ms"]:.3f}/{s["max_ms"]:.3f}' for v,s in stats.items()),flush=True)
(root/'native-controls.json').write_text(json.dumps(report,indent=2)+'\n')
