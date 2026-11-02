"""Balanced parser controls: full-value round trips and exact error compatibility."""
import argparse
import hashlib
import json
import pathlib
import platform
import statistics
import subprocess

p = argparse.ArgumentParser()
for name in ['before', 'after', 'rust', 'error-before', 'error-after', 'output']:
    p.add_argument('--' + name, type=pathlib.Path, required=True)
p.add_argument('--revision', required=True)
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=False)
root = pathlib.Path(__file__).resolve().parents[3]
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
versions = {'before': a.before.resolve(), 'after': a.after.resolve(), 'rust': a.rust.resolve()}
errors = {'before': a.error_before.resolve(), 'after': a.error_after.resolve()}
baseline = subprocess.check_output(['git', 'show', a.revision + ':stdlib/toml.ms'], cwd=root)
metadata = {'revision': a.revision, 'platform': platform.platform(), 'toolchain': subprocess.check_output(['rustc', '-vV'], text=True),
            'before_toml_sha256': hashlib.sha256(baseline).hexdigest(), 'after_toml_sha256': digest(root/'stdlib/toml.ms'),
            'binaries': {k: {'path': str(v), 'sha256': digest(v)} for k,v in versions.items()},
            'error_binaries': {k: {'path': str(v), 'sha256': digest(v)} for k,v in errors.items()},
            'source_and_runtime_sha256': {name: digest(root/name) for name in ['bench/perf/toml-control-scan/main.ms', 'bench/perf/toml-control-scan/error.ms', 'bench/perf/toml-control-scan/run.py', 'bench/perf/toml-control-scan/rust/src/main.rs', 'bench/perf/toml-control-scan/rust/Cargo.toml', 'bench/perf/toml-control-scan/rust/Cargo.lock', 'Cargo.lock', 'rust-toolchain.toml', '.cargo/config.toml', 'scripts/lld.lock', 'target/ms-native/libms_native.a']},
            'build': 'cargo xtask runtime; cargo build --release --locked -p ms-cli; ms build each unchanged source producer --build-type Release; Rust standalone Cargo release opt-level3 panic=abort with repository frame pointers',
            'trials': 12, 'note': 'Valid string-table parse+stringify: full equivalent values, possible different TOML quoting. Errors compare exact MS diagnostics only, no unmatched Rust error ratio. Setup outside timer, full output checks inside.'}
(a.output/'environment.json').write_text(json.dumps(metadata, indent=2)+'\n')
quote = lambda text: json.dumps(text, ensure_ascii=False)
fields = lambda count: ''.join(f'k{i:05} = {quote(f"user{i}-plain text")}\n' for i in range(count))
cases = {'empty': '', 'tiny': fields(1), 'fields32': fields(32), 'fields128': fields(128), 'fields512': fields(512),
         'unicode16k': 'value = '+quote('é🙂日本語'*1024)+'\n',
         'escapes': 'value = '+quote('a"\\\n\r\t\0\x1fé🙂'*1024)+'\n',
         'comment32k': '#'+'x'*32768+'\n'+fields(1),
         'comment1m': '#'+'x'*1048576+'\n'+fields(1),
         'literal1m': "value = '"+'abcdefgh'*131072+"'\n",
         'unicode1m': 'value = '+quote('é🙂日本語'*65536)+'\n'}
invalid = {'zero': ('\0', 'TOML 1:1: invalid control character'),
           'unicode': ('#é🙂 \0\n#\x7f', 'TOML 1:5: invalid control character'),
           'crlf-bare-cr': ('#é🙂\r\nx = 1\ry = 2', 'TOML 2:6: bare carriage return'),
           'syntax-first': ('???\n#\0', 'TOML 2:2: invalid control character'),
           'early1m': ('\0#'+'x'*1048576, 'TOML 1:1: invalid control character'),
           'late1m': ('#'+'x'*1048576+'\0', 'TOML 1:1048578: invalid control character')}
rows = []
for operation, payloads, binaries in [('roundtrip', cases, versions), ('error', invalid, errors)]:
    labels = list(binaries)
    for case, value in payloads.items():
        text, expected_error = (value, None) if operation == 'roundtrip' else value
        path = (a.output/f'{operation}-{case}.input').resolve()
        path.write_bytes(text.encode())
        outputs = {label: subprocess.check_output([binary, path, '0']) for label,binary in binaries.items()}
        if outputs['before'] != outputs['after']:
            raise ValueError(f'changed output: {operation}/{case}')
        if expected_error is not None and outputs['before'].decode() != expected_error:
            raise ValueError(f'wrong error diagnostic: {case}')
        sizes = {label: len(output) for label,output in outputs.items()}
        for label,output in outputs.items():
            out = (a.output/f'{operation}-{case}-{label}.out').resolve()
            out.write_bytes(output)
            if operation == 'roundtrip':
                subprocess.run([a.rust.resolve(), '--validate', path, out], check=True)
        def invoke(label, count):
            ns, checksum, size = map(int, subprocess.check_output([binaries[label], path, str(count)]).split())
            if ns <= 0 or size != sizes[label] or checksum != size * count:
                raise ValueError('invalid producer count/checksum')
            return ns / count
        counts = {}
        for label in labels:
            count = 1
            while True:
                ns = invoke(label, count)
                if ns * count >= 50_000_000 or count >= 1_000_000:
                    break
                count = min(max(count+1, int(60_000_000/ns)), count*10, 1_000_000)
            counts[label] = count
        for trial in range(12):
            order = labels[trial % len(labels):] + labels[:trial % len(labels)]
            if trial % 2:
                order.reverse()
            # For two labels use ordinary balanced AB/BA, avoiding the odd/even double rotation.
            if len(labels) == 2:
                order = labels if trial % 2 == 0 else list(reversed(labels))
            for label in order:
                row = dict(operation=operation, case=case, label=label, trial=trial, count=counts[label],
                           ns=invoke(label, counts[label]), input_bytes=len(text.encode()), input_sha256=digest(path), output_bytes=sizes[label])
                rows.append(row)
                with (a.output/'samples.jsonl').open('a') as log:
                    log.write(json.dumps(row)+'\n')
summary = []
for operation,payloads,binaries in [('roundtrip', cases, versions), ('error', invalid, errors)]:
    for case in payloads:
        distributions = {}
        for label in binaries:
            values = [r['ns'] for r in rows if r['operation']==operation and r['case']==case and r['label']==label]
            if len(values)!=12:
                raise ValueError('missing samples')
            m = statistics.median(values)
            distributions[label] = dict(median_ns=m, mad_ns=statistics.median(abs(x-m) for x in values), min_ns=min(values), max_ns=max(values))
        row = dict(operation=operation, case=case, distributions=distributions,
                   before_over_after=distributions['before']['median_ns']/distributions['after']['median_ns'])
        if operation == 'roundtrip':
            row['after_over_rust'] = distributions['after']['median_ns']/distributions['rust']['median_ns']
        summary.append(row)
(a.output/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
for row in summary:
    print(row['operation'], row['case'], row['before_over_after'], row.get('after_over_rust'))
