"""Separate whole-process RSS; includes setup, one guarded operation, and teardown."""
import argparse
import hashlib
import json
import pathlib
import statistics
import subprocess

p = argparse.ArgumentParser()
for name in ['environment', 'inputs', 'rss', 'output']:
    p.add_argument('--'+name, type=pathlib.Path, required=True)
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=False)
source = json.loads(a.environment.read_text())
groups = {'roundtrip': source['binaries'], 'error': source['error_binaries'], 'writer': source['writer_binaries'], 'read': source['read_binaries']}
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
for binaries in groups.values():
    for item in binaries.values():
        if digest(pathlib.Path(item['path'])) != item['sha256']:
            raise ValueError('binary differs from timing')
root = pathlib.Path(__file__).resolve().parents[3]
(a.output/'environment.json').write_text(json.dumps({'timing_environment_sha256':digest(a.environment),
    'source_environment':str(a.environment.resolve()), 'driver_sha256':digest(pathlib.Path(__file__)),
    'rss_sha256':digest(a.rss), 'rss_source_sha256':digest(root/'bench/perf/representative/rss.c'),
    'note':'Whole-process RSS includes setup and cached-file I/O, not allocation counts.'}, indent=2)+'\n')
cases = [('roundtrip','tiny'),('roundtrip','fields512'),('roundtrip','literal1m'),('roundtrip','unicode1m'),
         ('error','early1m'),('error','late1m'),('writer','dense'),('writer','unicode16k'),('read','unicode1m')]
rows = []
for operation,case in cases:
    path = (a.inputs/f'{operation}-{case}.input').resolve()
    binaries = groups[operation]
    labels = list(binaries)
    for trial in range(6):
        order = labels[trial % len(labels):]+labels[:trial % len(labels)]
        if trial%2:
            order.reverse()
        if len(labels)==2:
            order = labels if trial%2==0 else list(reversed(labels))
        for label in order:
            output = (a.inputs/f'{operation}-{case}-{label}.out').read_bytes()
            record = (a.output/f'{operation}-{case}-{label}-{trial}.json').resolve()
            result = subprocess.check_output([a.rss.resolve(), record, binaries[label]['path'], path, '1'])
            ns,checksum,size = map(int,result.split())
            if ns<=0 or checksum!=len(output) or size!=len(output):
                raise ValueError('wrong producer result')
            rows.append(dict(operation=operation,case=case,label=label,trial=trial,
                             input_sha256=digest(path),output_bytes=size,**json.loads(record.read_text())))
expected = {(op,case,label,trial) for op,case in cases for label in groups[op] for trial in range(6)}
if len(rows)!=len(expected) or {(r['operation'],r['case'],r['label'],r['trial']) for r in rows}!=expected:
    raise ValueError('missing/duplicate RSS samples')
(a.output/'samples.json').write_text(json.dumps(rows,indent=2)+'\n')
for op,case in cases:
    print(op,case,{label:statistics.median(r['maxrss_kib'] for r in rows if r['operation']==op and r['case']==case and r['label']==label) for label in groups[op]})
